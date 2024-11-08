# frozen_string_literal: true

module ReviewerOrnamentsConcern
  extend ActiveSupport::Concern

  REVIEW_ICON = {
    "UNREVIEWED" => "fa-solid fa-hourglass-start",
    "REVIEWED" => "fa-solid fa-check",
    "REQUESTED_CHANGES" => "fa-solid fa-ban",
    "APPROVED" => "fa-regular fa-thumbs-up",
    "UNAPPROVED" => "fa-solid fa-arrow-rotate-left",
    "REVIEW_STARTED" => "fa-solid fa-hourglass-half"
  }.freeze

  REVIEW_TEXT_BS_CLASS = {
    "UNREVIEWED" => "light",
    "REVIEWED" => "info",
    "REQUESTED_CHANGES" => "danger",
    "APPROVED" => "success",
    "UNAPPROVED" => "info",
    "REVIEW_STARTED" => "info"
  }.freeze

  def review_text_class(reviewer)
    REVIEW_TEXT_BS_CLASS[reviewer.mergeRequestInteraction.reviewState]
  end

  def review_icon_class(reviewer)
    REVIEW_ICON[reviewer.mergeRequestInteraction.reviewState]
  end
end
