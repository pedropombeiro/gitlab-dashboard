module MergeRequestsHelper
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::TagHelper
  include HumanizeHelper

  def user_help_hash(user)
    timezone = Services::TimezoneService.new.fetch_from_location(user.location)

    {
      Location: user.location,
      "Last activity": (user.lastActivityOn > 1.day.ago) ? "today" : "#{time_ago_in_words(user.lastActivityOn)} ago",
      "Local time": timezone&.time_with_offset(Time.now.utc)&.to_formatted_s,
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

  def tooltip_from_hash(hash)
    hash
      .filter_map { |title, value| value.present? ? tag.div("#{tag.b(title)}: #{value}", class: "text-start", escape: false) : nil }
      .join
  end
end
