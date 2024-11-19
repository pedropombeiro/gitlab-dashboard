class Admin::DashboardController < ApplicationController
  def index
    @recent_users = GitlabUser.recent
  end
end
