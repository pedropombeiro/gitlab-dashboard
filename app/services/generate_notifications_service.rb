# frozen_string_literal: true

require "async"

class GenerateNotificationsService
  include CacheConcern
  include WebPushConcern

  def initialize(author, type, fetch_service)
    @author_user = author.is_a?(GitlabUser) ? author : GitlabUser.find_by_username!(author)
    @type = type
    @fetch_service = fetch_service
  end

  def execute
    previous_dto = nil
    if author_user.web_push_subscriptions.any?
      response = cache_service.read(author_user.username, type)
      previous_dto = fetch_service.parse_dto(response, type)
    end

    response = fetch_service.execute(type)

    cache_service.write(author_user.username, type, response) if response.errors.nil?

    dto = fetch_service.parse_dto(response, type)
    check_changes(previous_dto, dto) if dto.errors.blank? && author_user.web_push_subscriptions.any?

    [response, dto]
  end

  private

  attr_reader :author_user, :type, :fetch_service

  def cache_service
    @cache_service ||= MergeRequestsCacheService.new
  end

  def check_changes(previous_dto, dto)
    notifications = ComputeMergeRequestChangesService.new(type, previous_dto, dto).execute
    if notifications.pluck(:type).include?(:merge_request_merged)
      # Clear monthly MR count cache if an MR has been merged
      Rails.cache.delete(self.class.monthly_merged_mr_lists_cache_key(author_user.username))
    end

    notifications.each { |notification| notify_user(**notification) }
  end

  def notify_user(title:, body:, icon: nil, badge: nil, url: nil, **message)
    icon ||= ActionController::Base.helpers.asset_url("apple-touch-icon-180x180.png")
    badge ||= ActionController::Base.helpers.asset_url("apple-touch-icon-120x120.png")

    publish(author_user, {
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
