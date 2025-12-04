# frozen_string_literal: true

class GroupReviewerPresenter < UserPresenter
  def initialize(reviewer, view_context = nil)
    super
    @reviewer = reviewer
  end

  def help_content
    view_context&.tooltip_from_hash(group_reviewer_help_hash) || tooltip_from_hash(group_reviewer_help_hash)
  end

  private

  attr_reader :reviewer

  def group_reviewer_help_hash
    {
      **help_hash,
      "Active reviews": safe_join([
        tag.span(reviewer.activeReviews.count.to_s),
        tag.a(
          tag.i(class: "bi bi-box-arrow-up-right small"),
          href: reviewer_dashboard_url,
          class: "ms-1", target: "_blank"
        )
      ])
    }
  end

  def reviewer_dashboard_url
    if view_context.respond_to?(:make_full_url)
      view_context.make_full_url("/dashboard/merge_requests/search?reviewer_username=#{reviewer.username}&not[approved_by_usernames][]=#{reviewer.username}")
    else
      "https://gitlab.com/dashboard/merge_requests?reviewer_username=#{reviewer.username}&state=opened&sort=updated_desc"
    end
  end
end
