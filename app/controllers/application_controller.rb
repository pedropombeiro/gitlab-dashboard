# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  def save_current_user(username)
    session[:user_id] = username
    @current_user = username.present? ? GitlabUser.safe_find_or_create_by!(username: username) : nil

    @current_user&.update_column(:contacted_at, Time.current)
  end

  def current_user
    return unless session[:user_id]
    @current_user ||= GitlabUser.find_by_username!(session[:user_id])
  end
end
