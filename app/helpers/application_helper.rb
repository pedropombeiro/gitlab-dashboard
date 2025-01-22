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

  def user_emojis(user_status)
    return unless user_status

    emojis = []

    emojis << if user_status.emoji == "speech_balloon" && user_status.message.scan(/:([\w+-]+):/).size == 1
      emojify(user_status.message)
    else
      user_emoji_character(user_status.emoji)
    end

    emojis << "🔴" if user_status.availability == "BUSY"

    emojis.uniq.join(" ")
  end

  def user_emoji_character(emoji_name)
    Emoji.find_by_alias(emoji_name)&.raw if emoji_name
  end

  def emojify(text)
    text&.gsub(/:([\w+-]+):/) do |match|
      user_emoji_character(Regexp.last_match(1)) || match
    end
  end

  def user_country_flag_classes(user)
    country_code = LocationLookupService.new.fetch_country_code(user.location)

    %W[fi fis fi-#{country_code.downcase}] if country_code
  end

  def format_location(user)
    return if user.location.blank?

    flag = tag.i(class: user_country_flag_classes(user))

    "#{flag} #{user.location}"
  end

  def user_help_hash(user)
    timezone = LocationLookupService.new.fetch_timezone(user.location)

    {
      "Job Title": user.jobTitle,
      Pronouns: user.pronouns,
      Location: format_location(user),
      "Local time": timezone&.time_with_offset(Time.now.utc)&.to_fs,
      "Last activity": format_last_activity(user.lastActivityOn),
      Message: [user_emoji_character(user.status&.emoji), emojify(user.status&.message)].compact.join(" ")
    }
  end

  def tooltip_from_hash(hash)
    hash
      .compact_blank
      .map { |title, value| tag.div("#{tag.b(title)}: #{value}", class: "text-start", escape: false) }
      .join
  end

  private

  def format_last_activity(last_activity_on)
    return if last_activity_on.nil?
    return "today" if last_activity_on.after?(1.day.ago)

    "#{time_ago_in_words(last_activity_on)} ago"
  end
end
