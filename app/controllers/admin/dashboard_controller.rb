class Admin::DashboardController < ApplicationController
  include CacheConcern

  helper_method :user_cache_validity

  def index
    @recent_users = GitlabUser.recent
  end

  private

  def user_cache_validity(assignee)
    response = Rails.cache.read(self.class.last_authored_mr_lists_cache_key(assignee))
    return unless response&.next_scheduled_update_at

    response.next_scheduled_update_at
  end
end
