require "gemoji"

module MergeRequestsHelper
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::TagHelper
  include HumanizeHelper

  def user_emojis(user_status)
    return unless user_status

    emojis = []

    emojis << if user_status.emoji == "speech_balloon" && user_status.message.scan(/:([\w+-]+):/).size == 1
      emojify(user_status.message)
    else
      user_emoji_character(user_status.emoji)
    end

    emojis << "🔴" if user_status.availability == "BUSY"

    emojis.uniq.join
  end

  def user_country_flag_classes(user)
    country_code = Services::LocationLookupService.new.fetch_country_code(user.location)

    %W[fi fis fi-#{country_code.downcase}] if country_code
  end

  def user_help_hash(user)
    timezone = Services::LocationLookupService.new.fetch_timezone(user.location)

    {
      Location: format_location(user),
      "Local time": timezone&.time_with_offset(Time.now.utc)&.to_fs,
      "Last activity": format_last_activity(user.lastActivityOn),
      Message: [user_emoji_character(user.status&.emoji), emojify(user.status&.message)].compact.join(" ")
    }
  end

  def user_help_title(user)
    tooltip_from_hash(user_help_hash(user))
  end

  def reviewer_help_title(reviewer)
    tooltip_from_hash(
      State: humanized_enum(reviewer.mergeRequestInteraction.reviewState),
      "Active reviews": reviewer.activeReviews.count,
      **user_help_hash(reviewer)
    )
  end

  def any_failed_pipeline?(merge_requests)
    merge_requests
      .flat_map { |mr| mr.headPipeline&.failedJobs&.nodes }
      .compact
      .map(&:allowFailure)
      .include?(false)
  end

  private

  def format_last_activity(last_activity_on)
    return "N/A" if last_activity_on.nil?
    return "today" if last_activity_on.after?(1.day.ago)

    "#{time_ago_in_words(last_activity_on)} ago"
  end

  def format_location(user)
    return if user.location.blank?

    flag = tag.i(class: user_country_flag_classes(user))

    "#{flag} #{user.location}"
  end

  def tooltip_from_hash(hash)
    hash
      .compact_blank
      .map { |title, value| tag.div("#{tag.b(title)}: #{value}", class: "text-start", escape: false) }
      .join
  end

  def user_emoji_character(emoji_name)
    Emoji.find_by_alias(emoji_name)&.raw if emoji_name
  end

  def emojify(text)
    text&.gsub(/:([\w+-]+):/) do |match|
      user_emoji_character(Regexp.last_match(1)) || match
    end
  end
end
