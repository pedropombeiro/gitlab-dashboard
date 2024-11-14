# frozen_string_literal: true

require "async"

module Services
  class FetchMergeRequestsService
    include CacheConcern

    def initialize(assignee)
      @assignee = assignee
    end

    def execute
      Rails.cache.fetch(self.class.authored_mr_lists_cache_key(assignee), expires_in: MR_CACHE_VALIDITY) do
        start_t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        gitlab_client = GitlabClient.new
        merge_requests = nil
        merged_merge_requests = nil

        Sync do
          # Fetch merge requests in 2 calls to reduce query complexity
          Async { merge_requests = gitlab_client.fetch_open_merge_requests(assignee) }
          Async { merged_merge_requests = gitlab_client.fetch_merged_merge_requests(assignee) }
        end

        end_t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        merge_requests.request_duration = (end_t - start_t).seconds.round(1)
        unless merge_requests.errors || merged_merge_requests.errors
          merge_requests.user.mergedMergeRequests = merged_merge_requests.user.mergedMergeRequests
          merge_requests.tap do |mrs|
            Rails.cache.write(self.class.last_authored_mr_lists_cache_key(assignee), mrs, expires_in: 1.week)
          end
        end
      end
    end

    private

    attr_reader :assignee
  end
end
