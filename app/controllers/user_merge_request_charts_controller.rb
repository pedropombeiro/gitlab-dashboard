class UserMergeRequestChartsController < MergeRequestsControllerBase
  def monthly_merged_merge_request_stats
    user = Rails.cache.fetch(
      self.class.monthly_merged_mr_lists_cache_key(safe_params[:assignee]),
      expires_in: MONTHLY_GRAPH_CACHE_VALIDITY
    ) do
      gitlab_client.fetch_monthly_merged_merge_requests(safe_params[:assignee])
    end.user

    render json: monthly_mrs_graph(user).map { |name, stats| {name: name, data: stats} }.chart_json
  end

  private

  def monthly_mrs_graph(user)
    pass1 = 12.times.map do |index|
      month = Time.current.beginning_of_month - index.months
      stats = user["monthlyMergedMergeRequests#{index}"]

      [
        month.strftime("%Y-%m"),
        {
          "Count" => stats.count,
          :"Average days to merge" =>
            stats.totalTimeToMerge ? (stats.totalTimeToMerge.seconds.in_days / stats.count).round(1) : nil
        }
      ]
    end.reverse

    pass1.each_with_object({}) do |(month, stats), acc|
      stats.each { |key, value|
        acc[key] ||= []
        acc[key] << [month, value]
      }
    end
  end
end
