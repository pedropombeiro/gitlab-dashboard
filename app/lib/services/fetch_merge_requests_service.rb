# frozen_string_literal: true

require "async"

module Services
  class FetchMergeRequestsService
    include Honeybadger::InstrumentationHelper

    include CacheConcern
    include HumanizeHelper
    include MergeRequestsHelper
    include MergeRequestsParsingHelper
    include MergeRequestsPipelineHelper

    attr_reader :assignee
    delegate :make_full_url, to: :gitlab_client

    def initialize(assignee, request_ip: nil)
      @assignee = assignee
      @request_ip = request_ip
    end

    def execute
      Rails.cache.fetch(self.class.authored_mr_lists_cache_key(assignee), expires_in: MergeRequestsCacheService.cache_validity) do
        open_mrs_response = nil
        merged_mrs_response = nil

        # Fetch merge requests in 2 calls to reduce query complexity, and do it asynchronously for efficiency
        Sync do
          [
            Async { open_mrs_response = gitlab_client.fetch_open_merge_requests(assignee) },
            Async { merged_mrs_response = gitlab_client.fetch_merged_merge_requests(assignee) }
          ].map(&:wait)
        end

        responses = [open_mrs_response, merged_mrs_response].compact
        response = open_mrs_response.response.data
        response.request_duration = responses.maximum(:request_duration) || 0
        response.updated_at = responses.minimum(:updated_at) || Time.current
        response.next_update_at = MergeRequestsCacheService.cache_validity.after(response.updated_at)
        response.next_scheduled_update_at =
          if any_running_pipelines?(response.user.openMergeRequests.nodes)
            5.minutes.from_now
          else
            30.minutes.from_now
          end
        response.errors = responses.map { |r| r.response.errors }.first

        if response.errors.nil?
          user2 = merged_mrs_response.response.data.user
          response.user.mergedMergeRequests = user2.mergedMergeRequests
          response.user.allMergedMergeRequests = user2.allMergedMergeRequests
          response.user.firstCreatedMergedMergeRequests = user2.firstCreatedMergedMergeRequests
        end

        if @request_ip
          metric_source "custom_metrics"
          metric_attributes(username: assignee, duration: response.request_duration, request_ip: @request_ip)

          increment_counter("user.visit")
        end

        response
      end
    end

    def parse_dto(response)
      open_issues_by_iid = []
      if response && response.errors.nil?
        open_merge_requests = response.user.openMergeRequests.nodes
        merged_merge_requests = response.user.mergedMergeRequests.nodes
        open_issues_by_iid = issues_from_merge_requests(open_merge_requests, merged_merge_requests)
      end

      ::UserDto.new(response, assignee, open_issues_by_iid)
    end

    private

    def gitlab_client
      @gitlab_client ||= GitlabClient.new
    end

    def any_running_pipelines?(merge_requests)
      merge_requests
        .filter_map(&:headPipeline)
        .any? { |pipeline| pipeline.startedAt.present? && pipeline.finishedAt.nil? }
    end

    def issues_from_merge_requests(open_merge_requests, merged_merge_requests)
      open_mr_issue_iids = merge_request_issue_iids(open_merge_requests).uniq
      merged_mr_issue_iids = merge_request_issue_iids(merged_merge_requests).uniq
      issue_iids = (open_mr_issue_iids + merged_mr_issue_iids).compact.uniq

      Rails.cache.fetch(self.class.project_issues_cache_key(issue_iids), expires_in: MergeRequestsCacheService.cache_validity) do
        gitlab_client.fetch_issues(merged_mr_issue_iids, open_mr_issue_iids)
      end.response&.data&.compact.to_h { |issue| [issue.iid, issue] }
    end
  end
end
