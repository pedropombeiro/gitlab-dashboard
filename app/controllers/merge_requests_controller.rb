# frozen_string_literal: true

require "async"

class MergeRequestsController < ApplicationController
  include CacheConcern
  include GitlabApiConcern
  include MrStatusOrnamentsConcern
  include ReviewerOrnamentsConcern

  MR_ISSUE_PATTERN = %r{[^\d]*(?<issue_id>\d+)[/-].+}i.freeze

  DEPLOYMENT_LABELS = ["Pick into auto-deploy"].freeze
  WORKFLOW_LABELS = WORKFLOW_LABELS_BS_CLASS.keys.freeze
  OPEN_MRS_CONTEXTUAL_LABELS = ["pipeline::"].freeze
  MERGED_MRS_CONTEXTUAL_LABELS = (DEPLOYMENT_LABELS + WORKFLOW_LABELS).freeze

  helper_method :humanized_enum, :make_full_url, :user_help_title, :reviewer_help_title

  def index
    assignee = params[:assignee]
    @user = Rails.cache.fetch(user_cache_key(assignee), expires_in: USER_CACHE_VALIDITY) do
      fetch_user(assignee)
    end.data.user

    unless params[:assignee] || Rails.application.credentials.gitlab_token
      return render(status: :network_authentication_required, plain: "Please configure GITLAB_TOKEN to use default user")
    end

    params[:assignee] = @user.username

    response = Rails.cache.read(last_authored_mr_lists_cache_key(params[:assignee]))

    parse_response(response)
    fresh_when(response)
  end

  def list
    assignee = params[:assignee]
    response = Rails.cache.fetch(authored_mr_lists_cache_key(assignee), expires_in: MR_CACHE_VALIDITY) do
      start_t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      merge_requests = nil
      merged_merge_requests = nil

      Sync do
        # Fetch merge requests in 2 calls to reduce query complexity
        Async { merge_requests = fetch_open_merge_requests(assignee) }
        Async { merged_merge_requests = fetch_merged_merge_requests(assignee) }
      end

      end_t = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      merge_requests.request_duration = (end_t - start_t).seconds.round(1)
      merge_requests.user.mergedMergeRequests = merged_merge_requests.user.mergedMergeRequests
      merge_requests.tap do |mrs|
        Rails.cache.write(last_authored_mr_lists_cache_key(assignee), mrs, expires_in: 1.week)
      end
    end

    parse_response(response)
    fresh_when(response)

    respond_to do |format|
      format.html
      format.json { render json: response }
    end
  end

  private

  def render_404
    respond_to do |format|
      format.html { render file: "#{Rails.root}/public/404.html", layout: false, status: :not_found }
      format.xml { head :not_found }
      format.any { head :not_found }
    end
  end

  def parse_graphql_time(timestamp)
    Time.parse(timestamp) if timestamp
  end

  def convert_mr_pipeline(pipeline)
    return unless pipeline

    failed_jobs = pipeline.failedJobs
    failed_job_traces = pipeline.failedJobTraces.nodes.select { |t| t.trace.present? }

    pipeline.startedAt = parse_graphql_time(pipeline.startedAt)
    pipeline.finishedAt = parse_graphql_time(pipeline.finishedAt)

    pipeline.webUrl =
      if pipeline.path
        web_path = pipeline.path

        # Try to make the user land in the most contextual page possible, depending on the state of the pipeline
        web_path =
          if failed_job_traces.count > 1
            "#{web_path}/failures"
          else
            case pipeline.status
            when "RUNNING"
              pipeline.summary = "#{helpers.pluralize(pipeline.runningJobs.count, "job")} still running"
              pipeline.status += " (#{pipeline.finishedJobs.count.to_i * 100 / pipeline.jobs.count.to_i}%)"

              pipeline.runningJobs.count == 1 ? pipeline.firstRunningJob.nodes.first.webPath : "#{web_path}/builds"
            when "FAILED"
              failed_job_traces.count == 1 ? failed_job_traces.first.webPath : "#{web_path}/failures"
            else
              web_path
            end
          end

        make_full_url(web_path)
      end

    tag = view_context.tag
    header = "#{helpers.pluralize(failed_jobs.count, "job")} #{helpers.pluralize_without_count(failed_jobs.count, "has", "have")} failed in the pipeline:"
    pipeline.failureSummary =
      if failed_job_traces.count == 1
        failed_job_trace = failed_job_traces.first

        [
          "#{header} #{tag.code(failed_job_trace.name, escape: false)}",
          "#{failed_job_trace.trace.htmlSummary}"
        ].join("<br/>")
      elsif failed_jobs.count.positive?
        <<~HTML
          #{header}<br/><br/>
          #{tag.ul(failed_jobs.nodes.map { |j| tag.li(tag.code(j.name)) }.join, escape: false)}
        HTML
      end

    pipeline.summary ||= pipeline.failureSummary if pipeline.status == "FAILED"
  end

  def convert_core_merge_request(merge_request, contextual_labels)
    merge_request.tap do |mr|
      mr.issue = issue_from_mr(mr)
      mr.createdAt = parse_graphql_time(mr.createdAt)
      mr.updatedAt = parse_graphql_time(mr.updatedAt)

      mr.contextualLabels = mr.labels.nodes.filter do |label|
        contextual_labels.any? { |prefix| label.title.start_with?(prefix) }
      end
    end
  end

  def convert_open_merge_request(merge_request)
    convert_core_merge_request(merge_request, OPEN_MRS_CONTEXTUAL_LABELS).tap do |mr|
      mr.bootstrapClass = {
        pipeline: pipeline_class(mr.headPipeline),
        mergeStatus: open_merge_request_status_class(mr)
      }

      convert_mr_pipeline(mr.headPipeline)

      mr.mergeStatusLabel = open_merge_request_status_label(mr)
      mr.labels.nodes.each { |label| label.bootstrapClass = [] } # Use label's predefined colors
      mr.reviewers.nodes.each do |reviewer|
        reviewer.lastActivityOn = parse_graphql_time(reviewer.lastActivityOn)
        reviewer.review = reviewer.mergeRequestInteraction.reviewState
        reviewer.bootstrapClass = {
          text: review_text_class(reviewer),
          icon: review_icon_class(reviewer),
          activity_icon: user_activity_icon_class(reviewer)
        }.compact
      end
    end
  end

  def convert_merged_merge_request(merge_request)
    convert_core_merge_request(merge_request, MERGED_MRS_CONTEXTUAL_LABELS).tap do |mr|
      mr.mergedAt = parse_graphql_time(mr.mergedAt)
      mr.mergeUser.lastActivityOn = parse_graphql_time(mr.mergeUser.lastActivityOn)

      mr.labels.nodes.each do |label|
        label.bootstrapClass = workflow_label_class(label.title)
        label.title.delete_prefix!(WORKFLOW_LABEL_NS)
      end
    end
  end

  def parse_response(response)
    return unless response

    @updated_at = response.updated_at
    @request_duration = response.request_duration
    @next_update =
      Rails.application.config.action_controller.perform_caching ? MR_CACHE_VALIDITY.after(response.updated_at) : nil
    open_mrs = response.user.openMergeRequests.nodes
    merged_mrs = response.user.mergedMergeRequests.nodes

    @open_issues_by_iid = issues_from_merge_requests(open_mrs, merged_mrs)
    @open_merge_requests = open_mrs.map { |mr| convert_open_merge_request(mr) }
    @merged_merge_requests = filter_merged_merge_requests(merged_mrs).map { |mr| convert_merged_merge_request(mr) }
  end

  def make_full_url(path)
    return path if path.nil? || path.start_with?("http")

    "#{gitlab_instance_url}#{path}"
  end

  def humanized_enum(value)
    value.tr("_", " ").capitalize.sub("Ci ", "CI ").strip
  end

  def tooltip_from_hash(hash)
    tag = view_context.tag

    hash
      .filter_map { |title, value| value.present? ? tag.div("#{tag.b(title)}: #{value}", class: "text-start", escape: false) : nil }
      .join
  end

  def user_help_hash(user)
    {
      "Location": user.location,
      "Last activity": user.lastActivityOn > 1.day.ago ? "today" : "#{helpers.time_ago_in_words(user.lastActivityOn)} ago",
      "Message": user.status&.message
    }
  end

  def user_help_title(user)
    tooltip_from_hash(user_help_hash(user))
  end

  def reviewer_help_title(reviewer)
    tooltip_from_hash(
      "State": humanized_enum(reviewer.mergeRequestInteraction.reviewState),
      "Active reviews": reviewer.activeReviews.count,
      **user_help_hash(reviewer)
    )
  end

  def user_activity_icon_class(user)
    %w[fa-solid fa-moon] if user.lastActivityOn < 1.day.ago
  end

  def issue_iid_from_mr(mr)
    match_data = MR_ISSUE_PATTERN.match(mr.sourceBranch)
    match_data&.named_captures&.fetch("issue_id")
  end

  def issue_from_mr(mr)
    iid = issue_iid_from_mr(mr)
    @open_issues_by_iid[iid]
  end

  def merge_request_issue_iids(merge_requests)
    merge_requests.to_h { |mr| [mr.iid, issue_iid_from_mr(mr)] }
  end

  def issues_from_merge_requests(open_merge_requests, merged_merge_requests)
    open_mr_issue_iids = merge_request_issue_iids(open_merge_requests).values.compact.sort.uniq
    merged_mr_issue_iids = merge_request_issue_iids(merged_merge_requests).values.compact.sort.uniq
    issue_iids = (open_mr_issue_iids + merged_mr_issue_iids).sort.uniq

    Rails.cache.fetch(open_issues_cache_key(issue_iids), expires_in: MR_CACHE_VALIDITY) do
      fetch_issues(merged_mr_issue_iids, open_mr_issue_iids)
    end&.to_h { |issue| [issue.iid, issue] }
  end

  def filter_merged_merge_requests(merge_requests)
    return unless @open_issues_by_iid

    open_mr_issue_iids = @open_issues_by_iid.keys
    merged_request_issue_iids = merge_request_issue_iids(merge_requests)

    merge_requests.filter do |mr|
      open_mr_issue_iids.include?(merged_request_issue_iids[mr.iid]) ||
        mr.mergedAt >= 2.days.ago
    end
  end
end
