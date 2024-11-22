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

    @dto = parse_dto(response, params[:assignee])
    fresh_when(response)
  end

  def list
    assignee = params[:assignee]
    ensure_assignee

    return render_404 unless current_user

    previous_dto = nil
    if current_user.web_push_subscriptions.any?
      response = Rails.cache.read(self.class.last_authored_mr_lists_cache_key(assignee))
      previous_dto = parse_dto(response, params[:assignee])
    end

    response = Services::FetchMergeRequestsService.new(assignee).execute

    @dto = parse_dto(response, params[:assignee])
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
    issue_iids = (open_mr_issue_iids + merged_mr_issue_iids).map { |h| h[:issue_iid] }.compact.sort.uniq

    Rails.cache.fetch(self.class.open_issues_cache_key(issue_iids), expires_in: cache_validity) do
      gitlab_client.fetch_issues(merged_mr_issue_iids, open_mr_issue_iids)
    end&.to_h { |issue| [issue.iid, issue] }
  end

  def notify_label_change(title, change)
    mr = change[:mr]

    notify_user(
      title: title,
      body: "changed to #{change[:labels].join(", ")}\n\n#{mr.reference}: #{mr.titleHtml}",
      url: mr.webUrl,
      tag: mr.iid,
      timestamp: mr.updatedAt
    )
  end

  def check_changes(previous_dto, dto)
    return unless previous_dto

    previous_open_mrs = previous_dto.open_merge_requests.items
    previous_merged_mrs = previous_dto.merged_merge_requests.items
    open_mrs = dto.open_merge_requests.items
    merged_mrs = dto.merged_merge_requests.items

    # Open MR merged
    merged_mrs.each do |mr|
      previous_mr_version = previous_open_mrs.find { |prev_mr| prev_mr.iid == mr.iid }
      next if previous_mr_version.nil?

      notify_user(
        title: "A merge request was merged",
        body: "#{mr.reference}: #{mr.titleHtml}",
        url: mr.webUrl,
        tag: mr.iid,
        timestamp: mr.updatedAt
      )
    end

    # Open MR changes
    changed_labels(previous_open_mrs, open_mrs).each do |change|
      notify_label_change("An open merge request", change)
    end

    # Merged MR changes
    changed_labels(previous_merged_mrs, merged_mrs).each do |change|
      notify_label_change("A merged merge request", change)
    end
  end

  def changed_labels(previous_mrs, mrs)
    return [] if previous_mrs.blank?

    mrs.filter_map do |mr|
      previous_mr_version = previous_mrs.find { |prev_mr| prev_mr.iid == mr.iid }
      next if previous_mr_version.nil?

      previous_labels = previous_mr_version.contextualLabels.map(&:webTitle)
      labels = mr.contextualLabels.map(&:webTitle)
      next if previous_labels.empty? || labels == previous_labels

      {
        mr: mr,
        labels: labels,
        previous_labels: previous_labels
      }
    end
  end
end
