# frozen_string_literal: true

class MergeRequestsControllerBase < ApplicationController
  include CacheConcern

  private

  def safe_params
    params.permit(:author, :referrer, :assignee)
  end

  def author
    username = safe_params[:author] || session[:user_id]
    validate_username(username) || username
  end

  def validate_username(username)
    return nil if username.blank?

    # GitLab usernames can only contain alphanumeric characters, underscores, dashes, and dots
    # They must start with alphanumeric and can't end with certain patterns
    unless username.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]*[a-zA-Z0-9]\z/) || username.match?(/\A[a-zA-Z0-9]\z/)
      Rails.logger.warn("Invalid username format: #{username}")
      return nil
    end

    # GitLab usernames have a maximum length of 255 characters
    return nil if username.length > 255

    username
  end

  def ensure_author
    unless author || Rails.application.credentials.gitlab_token
      render(status: :network_authentication_required, plain: "Please configure GITLAB_TOKEN to use default user")
      return false
    end

    true
  end
end
