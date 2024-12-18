# frozen_string_literal: true

require "async"

module Services
  class GenerateNotificationsService
    include CacheConcern
    include WebPushConcern

    def initialize(assignee, fetch_service)
      @assignee_user = GitlabUser.find_by_username!(assignee)
      @fetch_service = fetch_service
    end

    def execute
      fetch_service = FetchMergeRequestsService.new(assignee_user.username)
      previous_dto = nil
      if assignee_user.web_push_subscriptions.any?
        response = cache_service.read(assignee_user.username)
        previous_dto = fetch_service.parse_dto(response)
      end

      response = fetch_service.execute

      cache_service.write(assignee_user.username, response) if response.errors.nil?

      dto = fetch_service.parse_dto(response)
      check_changes(previous_dto, dto) if dto.errors.blank? && assignee_user.web_push_subscriptions.any?

      [response, dto]
    end

    private

    attr_reader :assignee_user

    def cache_service
      @cache_service ||= MergeRequestsCacheService.new
    end

    def check_changes(previous_dto, dto)
      notifications = Services::ComputeMergeRequestChangesService.new(previous_dto, dto).execute
      if notifications.pluck(:type).include?(:merge_request_merged)
        # Clear monthly MR count cache if an MR has been merged
        Rails.cache.delete(self.class.monthly_merged_mr_lists_cache_key(assignee_user.username))
      end

      notifications.each { |notification| notify_user(**notification) }
    end

    def notify_user(title:, body:, icon: nil, badge: nil, url: nil, **message)
      icon ||= ActionController::Base.helpers.asset_url("apple-touch-icon-180x180.png")
      badge ||= ActionController::Base.helpers.asset_url("apple-touch-icon-120x120.png")

      publish(assignee_user, {
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
