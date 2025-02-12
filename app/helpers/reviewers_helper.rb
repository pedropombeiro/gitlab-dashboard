module ReviewersHelper
  def reviewers_controller_params
    {group_path: params[:group_path]}
  end

  def assignee_dashboard_url(username)
    make_full_url("/dashboard/merge_requests/search?assignee_username=#{username}")
  end

  def reviewer_dashboard_url(username)
    make_full_url("/dashboard/merge_requests/search?reviewer_username=#{username}&not[approved_by_usernames][]=#{username}")
  end

  def group_reviewer_help_content(reviewer)
    tooltip_from_hash(
      **user_help_hash(reviewer),
      "Active reviews": safe_join([
        tag.span(reviewer.activeReviews.count.to_s),
        tag.a(
          tag.i(class: "bi bi-box-arrow-up-right small"),
          href: reviewer_dashboard_url(reviewer.username),
          class: "ms-1", target: "_blank"
        )
      ])
    )
  end
end
