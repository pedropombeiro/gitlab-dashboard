# frozen_string_literal: true

class WebPushSubscriptionsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :require_user

  def create
    @subscription = WebPushSubscription.create!(
      gitlab_user: current_user,
      endpoint: params[:endpoint],
      auth_key: params[:keys][:auth],
      p256dh_key: params[:keys][:p256dh]
    )

    head :ok
  end

  private

  def require_user
    unless current_user
      flash[:error] = "A user must be specified to access this section"
      redirect_back(fallback_location: root_path)
    end
  end
end
