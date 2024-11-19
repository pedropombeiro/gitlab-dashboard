module Admin::DashboardHelper
  def boot_timestamp
    GitlabDashboard::Application::BOOTED_AT
  end
end
