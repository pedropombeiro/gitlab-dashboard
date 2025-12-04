# frozen_string_literal: true

class ReviewerPresenter < UserPresenter
  include HumanizeHelper

  def initialize(reviewer, view_context = nil)
    super
    @reviewer = reviewer
  end

  def help_content
    view_context&.tooltip_from_hash(reviewer_help_hash) || tooltip_from_hash(reviewer_help_hash)
  end

  private

  attr_reader :reviewer

  def reviewer_help_hash
    {
      State: safe_join([
        tag.span(humanized_enum(reviewer.mergeRequestInteraction.reviewState), class: "me-1"),
        tag.i(class: [reviewer.bootstrapClass[:icon], "small"])
      ]),
      **help_hash,
      "Active reviews": safe_join([
        tag.span(reviewer.activeReviews.count.to_s),
        tag.a(
          tag.i(class: "bi bi-box-arrow-up-right small"),
          href: reviewer_dashboard_url(reviewer.username),
          class: "ms-1", target: "_blank", rel: "noopener"
        )
      ]),
      "Assigned MRs": tag.a(
        tag.i(class: "bi bi-box-arrow-up-right small"),
        href: assignee_dashboard_url(reviewer.username), target: "_blank", rel: "noopener"
      )
    }
  end

  def reviewer_dashboard_url(username)
    # Try to use view_context helper if available, otherwise construct URL
    if view_context.respond_to?(:make_full_url)
      view_context.make_full_url("/dashboard/merge_requests/search?reviewer_username=#{username}&not[approved_by_usernames][]=#{username}")
    else
      "https://gitlab.com/dashboard/merge_requests?reviewer_username=#{username}&state=opened&sort=updated_desc"
    end
  end

  def assignee_dashboard_url(username)
    # Try to use view_context helper if available, otherwise construct URL
    if view_context.respond_to?(:make_full_url)
      view_context.make_full_url("/dashboard/merge_requests/search?assignee_username=#{username}")
    else
      "https://gitlab.com/dashboard/merge_requests?assignee_username=#{username}&state=opened&sort=updated_desc"
    end
  end
end
