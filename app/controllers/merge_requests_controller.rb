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

    response = Rails.cache.read(self.class.last_authored_mr_lists_cache_key(params[:assignee]))

    @dto = parse_dto(response)
    fresh_when(response)
  end

  def list
    assignee = params[:assignee]
    ensure_assignee

    return render_404 unless current_user

    previous_dto = nil
    if current_user.web_push_subscriptions.any?
      response = Rails.cache.read(self.class.last_authored_mr_lists_cache_key(assignee))
      previous_dto = parse_dto(response)
    end

    response = MergeRequestsFetchJob.new.perform(assignee)

    @dto = parse_dto(response)
    if @dto.errors
      return respond_to do |format|
        format.html { render file: "#{Rails.root}/public/500.html", layout: false, status: :internal_server_error }
        format.xml { head :internal_server_error }
        format.any { head :internal_server_error }
      end
    end

    fresh_when(response)

    check_changes(previous_dto, @dto) if current_user.web_push_subscriptions.any?

    respond_to do |format|
      format.html
      format.json { render json: response }
    end
  end

  private

  def gitlab_client
    @gitlab_client ||= GitlabClient.new
  end

  def ensure_assignee
    unless params[:assignee] || Rails.application.credentials.gitlab_token
      return render(status: :network_authentication_required, plain: "Please configure GITLAB_TOKEN to use default user")
    end

    assignee = params[:assignee]
    @user = Rails.cache.fetch(self.class.user_cache_key(assignee), expires_in: USER_CACHE_VALIDITY) do
      gitlab_client.fetch_user(assignee)
    end.data.user

    assignee = @user&.username

    params[:assignee] = assignee
    save_current_user(assignee)
  end

  def render_404
    respond_to do |format|
      format.html { render file: "#{Rails.root}/public/404.html", layout: false, status: :not_found }
      format.xml { head :not_found }
      format.any { head :not_found }
    end
  end

  def parse_dto(response)
    open_issues_by_iid = []
    if response
      open_merge_requests = response.user.openMergeRequests.nodes
      merged_merge_requests = response.user.mergedMergeRequests.nodes
      open_issues_by_iid = issues_from_merge_requests(open_merge_requests, merged_merge_requests)
    end

    cache_validity =
      if Rails.application.config.action_controller.perform_caching
        MR_CACHE_VALIDITY
      else
        nil
      end

    ::MergeRequestsDto.new(response, open_issues_by_iid, cache_validity)
  end

  def issues_from_merge_requests(open_merge_requests, merged_merge_requests)
    open_mr_issue_iids = merge_request_issue_iids(open_merge_requests).values.compact.sort.uniq
    merged_mr_issue_iids = merge_request_issue_iids(merged_merge_requests).values.compact.sort.uniq
    issue_iids = (open_mr_issue_iids + merged_mr_issue_iids).sort.uniq

    Rails.cache.fetch(self.class.open_issues_cache_key(issue_iids), expires_in: MR_CACHE_VALIDITY) do
      gitlab_client.fetch_issues(merged_mr_issue_iids, open_mr_issue_iids)
    end&.to_h { |issue| [issue.iid, issue] }
  end

  def notify_label_change(mr)
    notify_user(
      title: "A merged MR changed",
      body: "#{mr.titleHtml} (#{mr.reference}) changed to #{change[:labels].join(", ")}",
      url: mr.webUrl,
      tag: mr.iid,
      timestamp: mr.updatedAt
    )
  end

  def check_changes(previous_dto, dto)
    return unless previous_dto

    # Open MR changes
    changed_labels(previous_dto.open_merge_requests, dto.open_merge_requests).each do |change|
      notify_label_change("An open MR changed", change[:mr])
    end

    # Merged MR changes
    changed_labels(previous_dto.merged_merge_requests, dto.merged_merge_requests).each do |change|
      notify_label_change("A merged MR changed", change[:mr])
    end
  end

  def changed_labels(previous_mrs, mrs)
    return [] unless previous_mrs

    mrs.filter_map do |mr|
      previous_mr_version = previous_mrs.select { |prev_mr| prev_mr.iid == mr.iid }.first
      next if previous_mr_version.nil?

      previous_labels = previous_mr_version.contextualLabels.map(&:title)
      labels = mr.contextualLabels.map(&:title)
      next unless labels != previous_labels

      {
        mr: mr,
        labels: labels,
        previous_labels: previous_labels
      }
    end
  end
end
