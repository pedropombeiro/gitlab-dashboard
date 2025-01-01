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
        # Fetch merge requests in 2 calls to reduce query complexity, and do it asynchronously for efficiency
        open_mrs_response, merged_mrs_response = Sync do |task|
          [
            task.async do
              gitlab_client.fetch_open_merge_requests(assignee).tap do |response|
                fill_reviewers_info(response.response.data.user.openMergeRequests.nodes)
              end
            end,
            task.async { gitlab_client.fetch_merged_merge_requests(assignee) }
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
      issues_by_iid = []
      if response && response.errors.nil?
        open_merge_requests = response.user.openMergeRequests.nodes
        merged_merge_requests = response.user.mergedMergeRequests.nodes
        issues_by_iid = issues_from_merge_requests(open_merge_requests, merged_merge_requests)
      end

      ::UserDto.new(response, assignee, issues_by_iid)
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

    def fill_reviewers_info(open_merge_requests)
      reviewer_usernames = open_merge_requests.flat_map { |mr| mr.reviewers.nodes.map(&:username) }.uniq

      reviewers_info = Sync do |task|
        reviewer_usernames.map do |reviewer_username|
          task.async do
            Rails.cache.fetch(self.class.reviewer_cache_key(reviewer_username), expires_in: 30.minutes) do
              gitlab_client.fetch_reviewer(reviewer_username)
            end
          end
        end.map(&:wait)
      end

      reviewers_hash =
        reviewers_info
          .map { |response| response.response.data.user }
          .to_h { |reviewer| [reviewer.username, reviewer] }

      open_merge_requests.flat_map { |mr| mr.reviewers.nodes }.each do |reviewer|
        reviewer.table.reverse_merge!(reviewers_hash[reviewer.username].table)

        if reviewer.activeReviews.nodes
          # NOTE: This is required because we can't filter on `active: true` reviews until
          # the `mr_approved_filter` FF is removed or enabled
          reviewer.activeReviews[:count] =
            reviewer.activeReviews.delete_field!(:nodes).count { |review| !review.approved }
        end
      end
    end
  end
end
