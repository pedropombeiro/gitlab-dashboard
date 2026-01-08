GitlabDashboard::Application::GIT_COMMIT_SHA =
  if Rails.application.respond_to?(:revision)
    Rails.application.revision
  else
    File.readable?("REVISION") ? File.read("REVISION").chomp : nil
  end
