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

  def recommended_monthly_merge_rate
    12
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

  def user_help_content(user)
    tooltip_from_hash(user_help_hash(user))
  end

  def user_help_title(user)
    tag.div(
      safe_join([
        render("shared/user_image", user: user, class: "me-1", size: 32),
        tag.span(
          safe_join([
            link_to(
              safe_join([
                tag.span(user.username, class: "me-1", data: {clipboard_target: "source"}),
                tag.i(class: "bi bi-box-arrow-up-right small")
              ]),
              user.webUrl, target: "_blank", rel: "noopener"
            ),
            render("shared/clipboard_button")
          ]),
          data: {controller: "clipboard"}
        )
      ])
    )
  end

  def merge_request_reviewer_help_content(reviewer)
    tooltip_from_hash(
      State: safe_join([
        tag.span(humanized_enum(reviewer.mergeRequestInteraction.reviewState), class: "me-1"),
        tag.i(class: [reviewer.bootstrapClass[:icon], "small"])
      ]),
      **user_help_hash(reviewer),
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
      target: "_blank", rel: "noopener"
    )
  end
end
