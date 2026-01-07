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

    # Broadcast real-time update to all connected clients via Turbo Streams
    if response.errors.nil?
      Rails.logger.info "[GenerateNotificationsService] Broadcasting update for #{author_user.username}/#{type}"
      MergeRequestBroadcaster.broadcast_update(author_user.username, type, dto)
    end

    if dto.errors.blank? && author_user.web_push_subscriptions.any?
      check_changes(previous_dto, dto, response.next_scheduled_update_at)
    end

    [response, dto]
  end

  private

  attr_reader :author_user, :type, :fetch_service

  def cache_service
    @cache_service ||= MergeRequestsCacheService.new
  end

  def check_changes(previous_dto, dto, next_scheduled_update_at)
    notifications = ComputeMergeRequestChangesService.new(type, previous_dto, dto).execute
    if notifications.pluck(:type).include?(:merge_request_merged)
      # Clear monthly MR count cache if an MR has been merged
      Rails.cache.delete(self.class.monthly_merged_mr_lists_cache_key(author_user.username))

      # Clear merged MRs cache if its next scheduled update is too far in the future,
      # since an MR might just have been merged and moved out of the open MRs list
      case type
      when :open
        cache_key = self.class.authored_mr_lists_cache_key(author_user.username, :merged)
        merged_response = Rails.cache.read(cache_key)
        if merged_response && merged_response.next_scheduled_update_at > next_scheduled_update_at
          Rails.cache.delete(cache_key)
        end
      when :merged
        cache_key = self.class.authored_mr_lists_cache_key(author_user.username, :open)
        open_response = Rails.cache.read(cache_key)
        if open_response && open_response.next_scheduled_update_at > next_scheduled_update_at
          Rails.cache.delete(cache_key)
        end
      end
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
