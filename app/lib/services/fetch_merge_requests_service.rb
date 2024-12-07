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
      return true unless response&.next_scheduled_update_at

      response.next_scheduled_update_at.past?
    end

    def execute
      Rails.cache.fetch(self.class.authored_mr_lists_cache_key(assignee), expires_in: self.class.cache_validity) do
        gitlab_client = GitlabClient.new
        open_mrs_response = nil
        merged_mrs_response = nil

        Sync do
          # Fetch merge requests in 2 calls to reduce query complexity
          Async { open_mrs_response = gitlab_client.fetch_open_merge_requests(assignee) }
          Async { merged_mrs_response = gitlab_client.fetch_merged_merge_requests(assignee) }
        end.wait

        response = open_mrs_response.response.data
        response.next_update_at = self.class.cache_validity.after(open_mrs_response.updated_at)
        response.next_scheduled_update_at =
          if any_running_pipelines?(response.user.openMergeRequests.nodes)
            5.minutes.from_now
          else
            30.minutes.from_now
          end
        response.errors = open_mrs_response&.response&.errors || merged_mrs_response&.response&.errors
        response.updated_at = [
          open_mrs_response&.updated_at || Time.current,
          merged_mrs_response&.updated_at || Time.current
        ].min
        response.request_duration = [
          open_mrs_response&.request_duration || 0,
          merged_mrs_response&.request_duration || 0
        ].max

        if response.errors.nil?
          user2 = merged_mrs_response.response.data.user
          response.user.mergedMergeRequests = user2.mergedMergeRequests
          response.user.allMergedMergeRequests = user2.allMergedMergeRequests
          response.user.firstCreatedMergedMergeRequests = user2.firstCreatedMergedMergeRequests
          Rails.cache.write(self.class.last_authored_mr_lists_cache_key(assignee), response, expires_in: 1.week)
        end

        response
      end
    end

    private

    attr_reader :assignee

    def any_running_pipelines?(merge_requests)
      merge_requests.any? do |mr|
        mr.headPipeline && mr.headPipeline.startedAt.present? && mr.headPipeline.finishedAt.nil?
      end
    end
  end
end
