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
        end.wait

        end_t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

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
  end
end
