# frozen_string_literal: true

class Api::UserMergeRequestChartsController < MergeRequestsControllerBase
  def monthly_merged_merge_request_stats
    return unless ensure_assignee

    response = Rails.cache.fetch(
      self.class.monthly_merged_mr_lists_cache_key(assignee),
      expires_in: MONTHLY_GRAPH_CACHE_VALIDITY
    ) do
      gitlab_client.fetch_monthly_merged_merge_requests(assignee)
    end

    render json: monthly_mrs_graph(response.response.data.user)
  end

  private

  def series_values(user, fn)
    12.times.map do |index|
      month = Time.current.beginning_of_month - index.months
      stats = user["monthlyMergedMergeRequests#{index}"]

      {
        x: month.strftime("%Y-%m"),
        y: fn.call(stats)
      }
    end.reverse
  end

  def monthly_mrs_graph(user)
    fetch_service = Services::FetchMergeRequestsService.new(params[:assignee])
    response = fetch_service.execute
    user_dto = fetch_service.parse_dto(response)
    since_first_mr = ActiveSupport::Duration.build(Time.current - user_dto.first_merged_merge_requests_timestamp)
    monthly_merge_rate = (user_dto.merged_merge_requests_count.to_f / since_first_mr.in_months.to_f).round

    {
      datasets: [
        {
          label: "Merged count",
          type: "bar",
          order: 2,
          data: series_values(user, ->(stats) { stats.count })
        },
        {
          label: "Average days to merge",
          type: "line",
          order: 1,
          data: series_values(user, ->(stats) do
            stats.totalTimeToMerge ? (stats.totalTimeToMerge.seconds.in_days / stats.count).round(1) : nil
          end)
        },
        {
          label: "Average merged per month",
          type: "line",
          order: 3,
          data: series_values(user, ->(stats) { monthly_merge_rate })
        }
      ]
    }
  end
end
