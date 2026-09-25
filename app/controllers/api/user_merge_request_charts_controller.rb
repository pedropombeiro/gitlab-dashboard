# frozen_string_literal: true

require "async"
require "ostruct"

class Api::UserMergeRequestChartsController < MergeRequestsControllerBase
  MONTHS_COUNT = 12
  EMPTY_MONTH_STATS = OpenStruct.new(count: 0, totalTimeToMerge: nil).freeze

  def monthly_merged_merge_request_stats
    return unless ensure_author

    render json: monthly_mrs_graph(monthly_stats)
  end

  private

  # Returns the stats for the last MONTHS_COUNT months, most recent first. Each month is cached
  # separately, so a refresh usually only needs to query the current month.
  def monthly_stats
    Sync do |task|
      MONTHS_COUNT.times.map do |offset|
        month = offset.months.ago.beginning_of_month.to_date

        task.async do
          Rails.cache.fetch(
            self.class.monthly_merged_mr_stats_cache_key(author, month),
            expires_in: self.class.monthly_merged_mr_stats_cache_validity(month),
            skip_nil: true
          ) do
            gitlab_client.fetch_monthly_merged_merge_request_stats(author, month)
          end || EMPTY_MONTH_STATS
        end
      end.map(&:wait)
    end
  end

  def series_values(monthly_stats, fn)
    monthly_stats.each_with_index.map do |stats, index|
      month = index.months.ago.beginning_of_month

      {
        x: month.strftime("%b"),
        y: fn.is_a?(Proc) ? fn.call(stats) : fn
      }
    end.reverse
  end

  def monthly_mrs_graph(monthly_stats)
    fetch_service = FetchMergeRequestsService.new(author)
    result = fetch_service.execute(:merged)
    user_dto = fetch_service.parse_dto(result.response, :merged)
    since_first_mr = ActiveSupport::Duration.build(
      user_dto.first_merged_merge_requests_timestamp ? Time.current - user_dto.first_merged_merge_requests_timestamp : 0
    )
    monthly_merge_rate = since_first_mr.positive? ?
      (user_dto.merged_merge_requests_count.to_f / since_first_mr.in_months.to_f).round : 0
    overall_monthly_merge_ttm = if user_dto.merged_merge_requests_count.positive? && user_dto.merged_merge_requests_tttm
      (user_dto.merged_merge_requests_tttm.seconds.in_days / user_dto.merged_merge_requests_count).round(1)
    else
      0
    end

    {
      datasets: [
        {
          label: "Average days to merge",
          type: "line",
          order: 1,
          backgroundColor: "#FF6384",
          borderColor: "#FF6384A0",
          data: series_values(monthly_stats, ->(stats) do
            stats.totalTimeToMerge ? (stats.totalTimeToMerge.seconds.in_days / stats.count).round(1) : nil
          end)
        },
        {
          label: "All-time average (#{helpers.pluralize(overall_monthly_merge_ttm.round, "day")})",
          type: "line",
          order: 1,
          backgroundColor: "#FF6384",
          borderColor: "#FF6384A0",
          pointStyle: false,
          borderDash: [10, 5],
          data: series_values(monthly_stats, overall_monthly_merge_ttm)
        },
        {
          label: "Merged count",
          type: "bar",
          stack: "merged-count",
          order: 2,
          backgroundColor: "#37A2EBA0",
          borderColor: "#37A2EB",
          data: series_values(monthly_stats, ->(stats) { stats.count }).take(11),
          trendlineLinear: {
            label: {
              color: "#000",
              text: "Merged MRs 11-month trendline",
              display: true,
              percentage: true,
              offset: 10
            },
            colorMin: "#37A2EBA0",
            lineStyle: "dotted",
            width: 2
          },
          datalabels: {
            align: "start",
            anchor: "end"
          }
        },
        {
          label: "MTD merged count",
          type: "bar",
          stack: "merged-count",
          order: 2,
          backgroundColor: "#37A2EB60",
          borderColor: "#37A2EB",
          data: series_values(monthly_stats, ->(stats) { stats.count }).drop(11)
        },
        {
          label: "All-time average (#{monthly_merge_rate.round}/month)",
          type: "line",
          order: 3,
          pointStyle: false,
          borderDash: [10, 5],
          borderColor: "#37A2EBA0",
          backgroundColor: "#37A2EBA0",
          data: series_values(monthly_stats, monthly_merge_rate)
        }
      ]
    }
  end
end
