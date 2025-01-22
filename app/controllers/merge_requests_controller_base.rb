# frozen_string_literal: true

class MergeRequestsControllerBase < ApplicationController
  include CacheConcern

  private

  def safe_params
    params.permit(:author, :referrer)
  end

  def author
    safe_params[:author] || session[:user_id]
  end

  def ensure_author
    unless author || Rails.application.credentials.gitlab_token
      render(status: :network_authentication_required, plain: "Please configure GITLAB_TOKEN to use default user")
      return false
    end

    true
  end
end
