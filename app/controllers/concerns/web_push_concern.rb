# frozen_string_literal: true

module WebPushConcern
  extend ActiveSupport::Concern

  def publish(user, message)
    user&.web_push_subscriptions&.each do |subscription|
      subscription.publish(message)
    rescue WebPush::ExpiredSubscription
      Rails.logger.info "Removing expired WebPush subscription"
      subscription.destroy
    rescue ActiveRecord::Encryption::Errors::Decryption
      Rails.logger.info "Invalid WebPush subscription"
      subscription.destroy
    end
  end
end
