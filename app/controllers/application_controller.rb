# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  delegate :make_full_url, to: :gitlab_client
  helper_method :make_full_url

  def save_current_user(username)
    session[:user_id] = username
    @current_user = username.present? ? GitlabUser.safe_find_or_create_by!(username: username) : nil

    return unless @current_user

    @current_user.update_columns(contacted_at: Time.current)
  end

  def current_user
    return unless session[:user_id]
    @current_user ||= GitlabUser.find_by_username!(session[:user_id])
  end

  private

  def gitlab_client
    @gitlab_client ||= GitlabClient.new
  end

  def render_404
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html").to_s, layout: false, status: :not_found }
      format.xml { head :not_found }
      format.any { head :not_found }
    end
  end
end
