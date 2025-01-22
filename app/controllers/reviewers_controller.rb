class ReviewersController < ApplicationController
  include CacheConcern
  include Honeybadger::InstrumentationHelper

  def index
    submit_metrics

    if safe_params.exclude?(:group_path)
      redirect_to reviewers_path(group_path: "gitlab-org/maintainers/cicd-verify") and return
    end
  end

  def list
    submit_metrics

    if safe_params.exclude?(:group_path)
      redirect_to reviewers_list_path(group_path: "gitlab-org/maintainers/cicd-verify") and return
    end

    group_path = safe_params[:group_path]
    response = Rails.cache.fetch(
      self.class.group_reviewers_cache_key(group_path), expires_in: GROUP_REVIEWERS_CACHE_VALIDITY
    ) do
      gitlab_client.fetch_group_reviewers(group_path)
    end

    reviewers = response.response.data.group&.groupMembers&.nodes
    return render_404 if reviewers.nil?

    @dto = GroupReviewersDto.new(response, group_path)
  end

  private

  def safe_params
    params.permit(:group_path)
  end

  def submit_metrics
    metric_source "custom_metrics"
    metric_attributes(path: request.path, request_ip: request.remote_ip)
    increment_counter("user.visit")
  end
end
