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
    GroupReviewerPresenter.new(reviewer, self).help_content
  end
end
