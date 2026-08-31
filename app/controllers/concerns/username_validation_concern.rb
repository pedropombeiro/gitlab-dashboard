# frozen_string_literal: true

module UsernameValidationConcern
  GITLAB_USERNAME_PATTERN = /\A[a-zA-Z0-9](?:[a-zA-Z0-9_.-]*[a-zA-Z0-9])?\z/
  GITLAB_USERNAME_MAX_LENGTH = 255

  private

  def validate_username(username)
    return nil if username.blank?

    # GitLab usernames can only contain alphanumeric characters, underscores, dashes, and dots.
    unless username.match?(GITLAB_USERNAME_PATTERN)
      Rails.logger.warn("Invalid username format: #{username}")
      return nil
    end

    # GitLab usernames have a maximum length of 255 characters.
    return nil if username.length > GITLAB_USERNAME_MAX_LENGTH

    username
  end
end
