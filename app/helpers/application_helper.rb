module ApplicationHelper
  GITHUB_REPO_URL = "https://github.com/pedropombeiro/gitlab-dashboard"

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
    return "#{GITHUB_REPO_URL}/releases/tag/#{git_release_tag}" if git_release_tag
    return "#{GITHUB_REPO_URL}/commit/#{git_commit_sha}" if git_commit_sha

    GITHUB_REPO_URL
  end

  def git_release_tag
    deployment_metadata(GitlabDashboard::Application::GIT_RELEASE_TAG)
  end

  def git_repo_link_title
    return "Release #{git_release_tag}" if git_release_tag
    return "Commit #{git_commit_sha.first(7)}" if git_commit_sha

    nil
  end

  def pluralize_without_count(count, noun, plural_noun = nil)
    (count == 1) ? noun.to_s : (plural_noun || noun.pluralize).to_s
  end

  def tooltip_from_hash(hash)
    tag.table(
      hash
        .compact_blank
        .map do |title, value|
          cells = [
            tag.td(tag.nobr(title, class: "me-1"), class: %W[text-end fw-bold align-text-top]),
            tag.td(value, escape: false)
          ]

          tag.tr(cells.join, escape: false)
        end.join
    )
  end

  private

  def git_commit_sha
    deployment_metadata(GitlabDashboard::Application::GIT_COMMIT_SHA)
  end

  def deployment_metadata(value)
    value.presence unless value == "null"
  end
end
