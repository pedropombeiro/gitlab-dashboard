# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  def save_current_user(username)
    session[:user_id] = username
    @current_user = username.present? ? GitlabUser.safe_find_or_create_by!(username: username) : nil
  end

  def current_user
    return unless session[:user_id]
    @current_user ||= GitlabUser.find_by_username!(session[:user_id])
  end

  def notify_user(title:, body:, icon: nil, badge: nil, **payload)
    icon ||= ActionController::Base.helpers.asset_url("apple-touch-icon-180x180.png")
    badge ||= ActionController::Base.helpers.asset_url("apple-touch-icon-120x120.png")
    merged_payload = {
      title: title,
      options: {
        badge: badge,
        body: body,
        icon: icon
      }.merge(payload)
    }

    current_user&.web_push_subscriptions.each do |subscription|
      subscription.publish(merged_payload)
    rescue WebPush::ExpiredSubscription
      Rails.logger.info "Removing expired WebPush subscription"
      subscription.destroy
    rescue ActiveRecord::Encryption::Errors::Decryption
      Rails.logger.info "Invalid WebPush subscription"
      subscription.destroy
    end
  end
end
