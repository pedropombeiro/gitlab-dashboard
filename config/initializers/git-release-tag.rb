GitlabDashboard::Application::GIT_RELEASE_TAG = File.readable?(".git-release-tag") ? File.read(".git-release-tag").chomp : nil
