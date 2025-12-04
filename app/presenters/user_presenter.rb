# frozen_string_literal: true

class UserPresenter
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::UrlHelper
  include ActionView::Context

  attr_reader :user, :view_context

  def initialize(user, view_context = nil)
    @user = user
    @view_context = view_context
  end

  def emojis
    return unless user.status

    emojis = []

    emojis << "🔴" if user.status.availability == "BUSY"

    emojis << if user.status.emoji == "speech_balloon" && user.status.message.scan(/:([\w+-]+):/).size == 1
      emojify(user.status.message)
    else
      emoji_character(user.status.emoji)
    end

    emojis.uniq.join(" ")
  end

  def emoji_character(emoji_name)
    Emoji.find_by_alias(emoji_name)&.raw if emoji_name
  end

  def country_flag_classes
    country_code = LocationLookupService.new.fetch_country_code(user.location)

    %W[fi fis fi-#{country_code.downcase}] if country_code
  end

  def formatted_location
    return if user.location.blank?

    flag = tag.i(class: country_flag_classes)

    "#{flag} #{user.location}"
  end

  def help_hash
    timezone = LocationLookupService.new.fetch_timezone(user.location)

    {
      "Job Title": user.jobTitle,
      Pronouns: user.pronouns,
      Location: formatted_location,
      "Local time": timezone&.time_with_offset(Time.now.utc)&.to_fs,
      "Last activity": formatted_last_activity,
      Message: [emoji_character(user.status&.emoji), emojify(user.status&.message)].compact.join(" ")
    }
  end

  def help_content
    view_context&.tooltip_from_hash(help_hash) || tooltip_from_hash(help_hash)
  end

  def help_title
    tag.div(
      safe_join([
        user_image,
        tag.span(
          safe_join([
            profile_link,
            clipboard_button
          ]),
          data: {controller: "clipboard"}
        )
      ])
    )
  end

  def emojify(text)
    text&.gsub(/:([\w+-]+):/) do |match|
      emoji_character(Regexp.last_match(1)) || match
    end
  end

  private

  def formatted_last_activity
    return if user.lastActivityOn.nil?
    return "today" if user.lastActivityOn.after?(1.day.ago)

    "#{ActionController::Base.helpers.time_ago_in_words(user.lastActivityOn)} ago"
  end

  def user_image
    return unless view_context

    view_context.render("shared/user_image", user: user, class: "me-1", size: 32)
  end

  def profile_link
    link_to(
      safe_join([
        tag.span(user.username, class: "h4 me-1", data: {clipboard_target: "source"}),
        tag.i(class: "bi bi-box-arrow-up-right small")
      ]),
      user.webUrl, target: "_blank", rel: "noopener"
    )
  end

  def clipboard_button
    return unless view_context

    view_context.render("shared/clipboard_button")
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
end
