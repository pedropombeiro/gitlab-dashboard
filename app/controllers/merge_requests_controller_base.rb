# frozen_string_literal: true

class MergeRequestsControllerBase < ApplicationController
  include CacheConcern
  include UsernameValidationConcern

  private

  def safe_params
    params.permit(:author, :referrer, :assignee)
  end

  def author
    username = safe_params[:author] || session[:user_id]
    validate_username(username) || username
  end

  def ensure_author
    unless author || GitlabClient.token?
      render(status: :network_authentication_required, plain: "Please configure GITLAB_TOKEN to use default user")
      return false
    end

    true
  end
end
