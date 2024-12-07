module MergeRequestsHelper
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::TagHelper
  include HumanizeHelper

  def user_country_flag_classes(user)
    country_code = Services::LocationLookupService.new.fetch_country_code(user.location)

    ["fi", "fis", "fi-#{country_code.downcase}"] if country_code
  end

  def user_help_hash(user)
    timezone = Services::LocationLookupService.new.fetch_timezone(user.location)

    {
      Location: format_location(user),
      "Local time": timezone&.time_with_offset(Time.now.utc)&.to_fs,
      "Last activity": user.lastActivityOn.after?(1.day.ago) ? "today" : "#{time_ago_in_words(user.lastActivityOn)} ago",
      Message: user.status&.message
    }.compact
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

  private

  def format_location(user)
    return if user.location.blank?

    tag.i(class: user_country_flag_classes(user)) + " " + user.location
  end

  def tooltip_from_hash(hash)
    hash
      .filter_map { |title, value| value.present? ? tag.div("#{tag.b(title)}: #{value}", class: "text-start", escape: false) : nil }
      .join
  end
end
