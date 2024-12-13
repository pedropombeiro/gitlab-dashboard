class Admin::DashboardController < ApplicationController
  helper_method :user_cache_validity

  def index
    @recent_users = GitlabUser.recent
  end

  private

  def user_cache_validity(assignee)
    response = Services::MergeRequestsCacheService.new.read(assignee)
    return unless response&.next_scheduled_update_at

    response.next_scheduled_update_at
  end
end
