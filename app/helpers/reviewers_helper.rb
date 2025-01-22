module ReviewersHelper
  def reviewers_controller_params
    {group_path: params[:group_path]}
  end

  def group_reviewer_help_title(reviewer)
    tooltip_from_hash(
      "Active reviews": reviewer.activeReviews.count,
      **user_help_hash(reviewer)
    )
  end
end
