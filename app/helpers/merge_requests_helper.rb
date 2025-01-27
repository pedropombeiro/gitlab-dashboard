require "gemoji"

module MergeRequestsHelper
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::TagHelper
  include HumanizeHelper

  def merge_requests_controller_params
    {author: params[:author], referrer: params[:referrer]}
  end

  def mr_age_limit
    2.weeks
  end

  def mr_list_panel_classes
    %w[
      table-responsive
      shadow
      align-middle
      border
      rounded
      bg-gradient
      p-2
    ]
  end

  def milestone_class(mr)
    return unless mr.milestone

    milestone_mismatch = mr.milestone.title != (mr.issue&.milestone&.title || mr.milestone.title)
    milestone_mismatch ||= mr.project.version && !mr.project.version.start_with?(mr.milestone.title)
    milestone_mismatch ? "text-warning" : nil
  end

  def mttm_handbook_url
    handbook_url("the handbook", "product/groups/product-analysis/engineering/metrics/#mean-time-to-merge-mttm")
  end

  def merged_mr_rates_handbook_url
    handbook_url("the handbook", "product/groups/product-analysis/engineering/metrics/#merge-request-rates-mr-rates")
  end

  def milestone_mismatch_tooltip(mr)
    return unless mr.milestone

    if mr.milestone.title != (mr.issue&.milestone&.title || mr.milestone.title)
      return "Merge request is assigned to #{mr.milestone.title} but issue is assigned to #{mr.issue&.milestone&.title}"
    end

    if mr.project.version && !mr.project.version.start_with?(mr.milestone.title)
      "Merge request is assigned to #{mr.milestone.title} but the active milestone for the project is #{mr.project.version}"
    end
  end

  def user_help_title(user)
    tooltip_from_hash(user_help_hash(user))
  end

  def merge_request_reviewer_help_title(reviewer)
    tooltip_from_hash(
      State: humanized_enum(reviewer.mergeRequestInteraction.reviewState),
      "Active reviews": reviewer.activeReviews.count,
      **user_help_hash(reviewer)
    )
  end

  def any_failed_pipeline?(merge_requests)
    merge_requests
      .flat_map { |mr| mr.headPipeline&.failedJobs&.nodes }
      .compact
      .map(&:allowFailure)
      .include?(false)
  end

  private

  def handbook_url(title, path)
    tag.a(
      "the handbook",
      href: "https://handbook.gitlab.com/handbook/" + path,
      target: "_blank"
    )
  end
end
