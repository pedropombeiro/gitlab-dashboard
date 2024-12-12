# frozen_string_literal: true

require "async"

module Services
  class FetchMergeRequestsService
    include CacheConcern
    include HumanizeHelper
    include MergeRequestsParsingHelper
    include MergeRequestsHelper
    include MergeRequestsPipelineHelper
    include WebPushConcern

    attr_reader :assignee
    delegate :make_full_url, to: :gitlab_client

    def self.cache_validity
      if Rails.application.config.action_controller.perform_caching
        MR_CACHE_VALIDITY
      else
        1.minute
      end
    end

    def initialize(assignee)
      @current_user = assignee.is_a?(String) ? GitlabUser.find_by_username!(assignee) : assignee
      @assignee = @current_user.username
    end

    def needs_scheduled_update?
      response = Rails.cache.read(self.class.last_authored_mr_lists_cache_key(assignee))
      return true unless response&.next_scheduled_update_at

      response.next_scheduled_update_at.past?
    end

    def execute
      previous_dto = nil
      if current_user.web_push_subscriptions.any?
        response = Rails.cache.read(self.class.last_authored_mr_lists_cache_key(assignee))
        previous_dto = parse_dto(response)
      end

      response = Rails.cache.fetch(
        self.class.authored_mr_lists_cache_key(assignee),
        expires_in: self.class.cache_validity
      ) do
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

      dto = parse_dto(response)
      check_changes(previous_dto, dto) if dto.errors.blank? && current_user.web_push_subscriptions.any?

      [response, dto]
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

    attr_reader :current_user

    def gitlab_client
      @gitlab_client ||= GitlabClient.new
    end

    def any_running_pipelines?(merge_requests)
      merge_requests.any? do |mr|
        mr.headPipeline && mr.headPipeline.startedAt.present? && mr.headPipeline.finishedAt.nil?
      end
    end

    def issues_from_merge_requests(open_merge_requests, merged_merge_requests)
      open_mr_issue_iids = merge_request_issue_iids(open_merge_requests).uniq
      merged_mr_issue_iids = merge_request_issue_iids(merged_merge_requests).uniq
      issue_iids = (open_mr_issue_iids + merged_mr_issue_iids).pluck(:issue_iid).compact.sort.uniq

      Rails.cache.fetch(self.class.open_issues_cache_key(issue_iids), expires_in: self.class.cache_validity) do
        gitlab_client.fetch_issues(merged_mr_issue_iids, open_mr_issue_iids)
      end.response&.data.to_h { |issue| [issue.iid, issue] }
    end

    def check_changes(previous_dto, dto)
      notifications = Services::ComputeMergeRequestChangesService.new(previous_dto, dto).execute

      notifications.each { |notification| notify_user(**notification) }
    end

    def notify_user(title:, body:, icon: nil, badge: nil, url: nil, **message)
      icon ||= ActionController::Base.helpers.asset_url("apple-touch-icon-180x180.png")
      badge ||= ActionController::Base.helpers.asset_url("apple-touch-icon-120x120.png")

      publish(current_user, {
        type: "push_notification",
        payload: {
          title: title,
          options: {
            badge: badge,
            body: body,
            data: url ? {url: url} : nil,
            icon: icon
          }.compact.merge(message)
        }
      })
    end
  end
end
