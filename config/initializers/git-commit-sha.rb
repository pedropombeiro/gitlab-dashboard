GitlabDashboard::Application::GIT_COMMIT_SHA = File.readable?(".git-sha") ? File.read(".git-sha").chomp : nil
