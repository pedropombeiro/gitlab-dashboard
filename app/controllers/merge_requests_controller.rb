# frozen_string_literal: true

class MergeRequestsController < ApplicationController
  helper MergeRequestsHelper
  helper MergeRequestsPipelineHelper

  include CacheConcern
  include HumanizeHelper
  include MergeRequestsParsingHelper

  delegate :make_full_url, to: :gitlab_client
  helper_method :make_full_url

  def index
    ensure_assignee

    @user = Rails.cache.fetch(self.class.user_cache_key(safe_params[:assignee]), expires_in: USER_CACHE_VALIDITY) do
      gitlab_client.fetch_user(safe_params[:assignee])
    end.data.user

    render_404 and return unless @user

    save_current_user(safe_params[:assignee])
    if @user.username != safe_params[:assignee]
      redirect_to merge_requests_path(assignee: @user.username) and return
    end

    response = Rails.cache.read(self.class.last_authored_mr_lists_cache_key(safe_params[:assignee]))

    @dto = parse_dto(response, safe_params[:assignee])
    fresh_when(response)
  end

  def list
    ensure_assignee
    render_404 and return unless current_user

    assignee = safe_params[:assignee]
    save_current_user(assignee)
    previous_dto = nil
    if current_user.web_push_subscriptions.any?
      response = Rails.cache.read(self.class.last_authored_mr_lists_cache_key(assignee))
      previous_dto = parse_dto(response, assignee)
    end

    response = Services::FetchMergeRequestsService.new(assignee).execute

    @dto = parse_dto(response, assignee)
    if @dto.errors
      return respond_to do |format|
        format.html { render file: Rails.public_path.join("500.html").to_s, layout: false, status: :internal_server_error }
        format.any { head :internal_server_error }
      end
    end

    fresh_when(response)

    check_changes(previous_dto, @dto) if current_user.web_push_subscriptions.any?

    respond_to do |format|
      format.html { redirect_to merge_requests_path(assignee: assignee) unless params[:turbo] }
      format.json { render json: response }
    end
  end

  private

  def gitlab_client
    @gitlab_client ||= GitlabClient.new
  end

  def safe_params
    params.permit(:assignee)
  end

  def ensure_assignee
    unless safe_params[:assignee] || Rails.application.credentials.gitlab_token
      return render(status: :network_authentication_required, plain: "Please configure GITLAB_TOKEN to use default user")
    end
  end

  def render_404
    respond_to do |format|
      format.html { render file: Rails.public_path.join("404.html").to_s, layout: false, status: :not_found }
      format.xml { head :not_found }
      format.any { head :not_found }
    end
  end

  def parse_dto(response, assignee)
    open_issues_by_iid = []
    if response && response.errors.nil?
      open_merge_requests = response.user.openMergeRequests.nodes
      merged_merge_requests = response.user.mergedMergeRequests.nodes
      open_issues_by_iid = issues_from_merge_requests(open_merge_requests, merged_merge_requests)
    end

    ::UserDto.new(response, assignee, open_issues_by_iid)
  end

  def cache_validity
    Services::FetchMergeRequestsService.cache_validity
  end

  def issues_from_merge_requests(open_merge_requests, merged_merge_requests)
    open_mr_issue_iids = merge_request_issue_iids(open_merge_requests).uniq
    merged_mr_issue_iids = merge_request_issue_iids(merged_merge_requests).uniq
    issue_iids = (open_mr_issue_iids + merged_mr_issue_iids).pluck(:issue_iid).compact.sort.uniq

    Rails.cache.fetch(self.class.open_issues_cache_key(issue_iids), expires_in: cache_validity) do
      gitlab_client.fetch_issues(merged_mr_issue_iids, open_mr_issue_iids)
    end&.to_h { |issue| [issue.iid, issue] }
  end

  def check_changes(previous_dto, dto)
    notifications = Services::ComputeMergeRequestChangesService.new(previous_dto, dto).execute

    notifications.each { |notification| notify_user(**notification) }
  end
end
