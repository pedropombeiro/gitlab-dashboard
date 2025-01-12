# frozen_string_literal: true

class MergeRequestsControllerBase < ApplicationController
  include CacheConcern

  private

  def gitlab_client
    @gitlab_client ||= GitlabClient.new
  end

  def safe_params
    params.permit(:author)
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

  def render_404
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html").to_s, layout: false, status: :not_found }
      format.xml { head :not_found }
      format.any { head :not_found }
    end
  end
end
