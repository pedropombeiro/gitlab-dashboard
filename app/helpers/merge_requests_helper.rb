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

  def mttm_handbook_url
    handbook_url("the handbook", "product/groups/product-analysis/engineering/metrics/#mean-time-to-merge-mttm")
  end

  def merged_mr_rates_handbook_url
    handbook_url("the handbook", "product/groups/product-analysis/engineering/metrics/#merge-request-rates-mr-rates")
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
