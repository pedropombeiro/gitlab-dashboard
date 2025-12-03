# frozen_string_literal: true

class Api::WebPushSubscriptionsController < ApplicationController
  before_action :require_user
  before_action :verify_origin

  def create
    params.expect(:endpoint, keys: [:auth, :p256dh])

    @subscription = WebPushSubscription.create!(
      gitlab_user: current_user,
      endpoint: params[:endpoint],
      auth_key: params[:keys][:auth],
      p256dh_key: params[:keys][:p256dh]
    ) do |sub|
      sub.user_agent = request.user_agent
    end

    Honeybadger.event(
      "Created web push subscription",
      gitlab_user: current_user.username,
      user_agent: request.user_agent
    )

    head :ok
  end

  private

  def require_user
    unless current_user
      head :unauthorized
    end
  end

  def verify_origin
    return if request.origin.blank?

    allowed_origins = [
      request.base_url,
      "https://#{request.host}",
      ("http://#{request.host}" if Rails.env.development?)
    ].compact

    unless allowed_origins.include?(request.origin)
      Rails.logger.warn("Web push subscription rejected: invalid origin #{request.origin}")
      head :forbidden
    end
  end
end
