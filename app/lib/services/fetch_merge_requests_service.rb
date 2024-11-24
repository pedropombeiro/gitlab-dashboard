# frozen_string_literal: true

require "async"

module Services
  class FetchMergeRequestsService
    include CacheConcern

    def self.cache_validity
      if Rails.application.config.action_controller.perform_caching
        MR_CACHE_VALIDITY
      else
        1.minute
      end
    end

    def initialize(assignee)
      @assignee = assignee
    end

    def needs_scheduled_update?
      response = Rails.cache.read(self.class.last_authored_mr_lists_cache_key(assignee))
      return true if response&.next_scheduled_update_at&.nil?

      response.next_scheduled_update_at.past?
    end

    def execute
      Rails.cache.fetch(self.class.authored_mr_lists_cache_key(assignee), expires_in: self.class.cache_validity) do
        start_t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        gitlab_client = GitlabClient.new
        merge_requests = nil
        merged_merge_requests = nil

        Sync do
          # Fetch merge requests in 2 calls to reduce query complexity
          Async { merge_requests = gitlab_client.fetch_open_merge_requests(assignee) }
          Async { merged_merge_requests = gitlab_client.fetch_merged_merge_requests(assignee) }
        end.wait

        end_t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        merge_requests.next_update_at = self.class.cache_validity.after(merge_requests.updated_at)
        merge_requests.next_scheduled_update_at =
          if any_running_pipelines?(merge_requests.user.openMergeRequests.nodes)
            5.minutes.from_now
          else
            30.minutes.from_now
          end
        merge_requests.request_duration = (end_t - start_t).seconds.round(1)
        merge_requests.errors ||= merged_merge_requests&.errors
        if merge_requests.errors.nil?
          merge_requests.user.mergedMergeRequests = merged_merge_requests.user.mergedMergeRequests
          Rails.cache.write(self.class.last_authored_mr_lists_cache_key(assignee), merge_requests, expires_in: 1.week)
        end

        merge_requests
      end
    end

    private

    attr_reader :assignee

    def any_running_pipelines?(merge_requests)
      merge_requests.any? { |mr| mr.headPipeline.startedAt.present? && mr.headPipeline.finishedAt.nil? }
    end
  end
end
