module ApplicationHelper
  def safe_url(url)
    uri = URI.parse(url)

    if uri.relative? && uri.path.present?
      uri.to_s if uri.is_a?(URI::Generic)
    elsif uri.absolute? && uri.is_a?(URI::HTTPS) && uri.host == "app.honeybadger.io"
      uri.to_s
    else
      "/"
    end
  rescue URI::InvalidURIError
    "/"
  end

  def git_repo_url
    repo_url = "https://github.com/pedropombeiro/gitlab-dashboard"
    commit_sha = GitlabDashboard::Application::GIT_COMMIT_SHA

    return "#{repo_url}/commit/#{commit_sha}" if commit_sha.present?

    repo_url
  end

  def pluralize_without_count(count, noun, plural_noun = nil)
    (count == 1) ? noun.to_s : (plural_noun || noun.pluralize).to_s
  end
end
