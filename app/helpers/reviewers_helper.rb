module ReviewersHelper
  def reviewers_controller_params
    {group_path: params[:group_path]}
  end

  # Utility methods for constructing reviewer dashboard URLs
  def assignee_dashboard_url(username)
    make_full_url("/dashboard/merge_requests/search?assignee_username=#{username}")
  end

  def reviewer_dashboard_url(username)
    make_full_url("/dashboard/merge_requests/search?reviewer_username=#{username}&not[approved_by_usernames][]=#{username}")
  end
end
