class Admin::DashboardController < ApplicationController
  helper_method :user_cache_validity

  def index
    @users = GitlabUser.all
    @recent_users = GitlabUser.recent.order_by_contacted_at_desc
    @active_users = GitlabUser.active.order_by_contacted_at_desc
  end

  private

  def user_cache_validity(assignee)
    response = MergeRequestsCacheService.new.read(assignee)
    return unless response&.next_scheduled_update_at

    response.next_scheduled_update_at
  end
end
