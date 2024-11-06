# frozen_string_literal: true

require "ostruct"

class MergeRequestsController < ApplicationController
  MR_ISSUE_PATTERN = %r{[^\d]*(?<issue_id>\d+)[/-].+}i.freeze
  USER_CACHE_VALIDITY = 1.day
  MR_CACHE_VALIDITY = 5.minutes

  PIPELINE_BS_CLASS = { "SUCCESS" => "success", "FAILED" => "danger", "RUNNING" => "primary" }.freeze
  MERGE_STATUS_BS_CLASS = { "BLOCKED_STATUS" => "warning", "CI_STILL_RUNNING" => "primary", "MERGEABLE" => "success" }.freeze
  REVIEW_ICON = {
    "UNREVIEWED" => "fa-solid fa-hourglass-start",
    "REVIEWED" => "fa-solid fa-check",
    "REQUESTED_CHANGES" => "fa-solid fa-ban",
    "APPROVED" => "fa-regular fa-thumbs-up",
    "UNAPPROVED" => "fa-solid fa-arrow-rotate-left",
    "REVIEW_STARTED" => "fa-solid fa-hourglass-half"
  }.freeze
  REVIEW_TEXT_BS_CLASS = {
    "UNREVIEWED" => "dark",
    "REVIEWED" => "secondary",
    "REQUESTED_CHANGES" => "danger",
    "APPROVED" => "success",
    "UNAPPROVED" => "info",
    "REVIEW_STARTED" => "info"
  }.freeze
  WORKFLOW_LABELS_BS_CLASS = {
    "workflow::staging-canary" => "info",
    "workflow::canary" => "info",
    "workflow::staging" => "info",
    "workflow::production" => "primary",
    "workflow::post-deploy-db-staging" => "success",
    "workflow::post-deploy-db-production" => "success"
  }.freeze
  DEPLOYMENT_LABELS = ["Pick into auto-deploy"].freeze
  WORKFLOW_LABELS = WORKFLOW_LABELS_BS_CLASS.keys.freeze
  OPEN_MRS_CONTEXTUAL_LABELS = ["pipeline::"].freeze
  MERGED_MRS_CONTEXTUAL_LABELS = (DEPLOYMENT_LABELS + WORKFLOW_LABELS).freeze

  CORE_USER_FRAGMENT = <<-GRAPHQL
      fragment CoreUserFields on User {
        username
        avatarUrl
        webUrl
      }
    GRAPHQL

  EXT_USER_FRAGMENT = <<-GRAPHQL
      fragment ExtendedUserFields on User {
        ...CoreUserFields
        lastActivityOn
        location
        status {
          availability
          message
        }
      }
    GRAPHQL

  CORE_ISSUE_FRAGMENT = <<-GRAPHQL
      fragment CoreIssueFields on Issue {
        iid
        webUrl
        titleHtml
      }
    GRAPHQL

  CORE_MERGE_REQUEST_FRAGMENT = <<-GRAPHQL
      fragment CoreMergeRequestFields on MergeRequest {
        iid
        webUrl
        titleHtml
        reference
        sourceBranch
        targetBranch
        createdAt
        updatedAt
        assignees {
          nodes { ...CoreUserFields }
        }
        labels {
          nodes {
            title
            descriptionHtml
            color
            textColor
          }
        }
      }
    GRAPHQL

  helper_method :humanized_enum, :make_full_url, :user_help_title, :reviewer_help_title

  def index
    @user = fetch_user(params[:assignee])
    unless params[:assignee] || ENV["GITLAB_TOKEN"]
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
      # Fetch merge requests in 2 calls to reduce query complexity
      merge_requests = fetch_open_merge_requests(assignee)
      merge_requests.user.mergedMergeRequests = fetch_merged_merge_requests(assignee).user.mergedMergeRequests

      merge_requests.tap do |mrs|
        Rails.cache.write(last_authored_mr_lists_cache_key(assignee), mrs)
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

  def user_hash(username)
    Digest::SHA256.hexdigest(username || ENV["GITLAB_TOKEN"] || "Anonymous")[0..15]
  end

  def fetch_user(username)
    response = Rails.cache.fetch("user_info_v2/#{user_hash(username)}", expires_in: USER_CACHE_VALIDITY) do
      response = client.query <<-GRAPHQL
        query {
          user: #{username ? "user(username: \"#{username}\")" : "currentUser"} {
            ...CoreUserFields
          }
        }

        #{CORE_USER_FRAGMENT}
      GRAPHQL

      make_serializable(response)
    end

    response.data.user
  end

  def render_404
    respond_to do |format|
      format.html { render file: "#{Rails.root}/public/404.html", layout: false, status: :not_found }
      format.xml { head :not_found }
      format.any { head :not_found }
    end
  end

  def gitlab_instance_url
    @gitlab_instance_url ||= ENV.fetch("GITLAB_URL", "https://gitlab.com")
  end

  def authorization
    "Bearer #{ENV["GITLAB_TOKEN"]}"
  end

  def client
    ::Graphlient::Client.new(
      "#{gitlab_instance_url}/api/graphql",
      headers: { "Authorization" => authorization },
      http_options: {
        read_timeout: 20,
        write_timeout: 30
      }
    )
  end

  def parse_graphql_time(timestamp)
    Time.parse(timestamp) if timestamp
  end

  def fetch_open_merge_requests(username)
    merge_requests_graphql_query = <<-GRAPHQL
      query($username: String!, $activeReviewsAfter: Time) {
        user(username: $username) {
          openMergeRequests: authoredMergeRequests(state: opened, sort: UPDATED_DESC) {
            nodes {
              ...CoreMergeRequestFields
              approved
              approvalsRequired
              approvalsLeft
              autoMergeEnabled
              detailedMergeStatus
              squashOnMerge
              conflicts
              blockingMergeRequests {
                visibleMergeRequests {
                  state
                }
              }
              reviewers {
                nodes {
                  ...ExtendedUserFields
                  mergeRequestInteraction {
                    approved
                    reviewState
                  }
                  activeReviews: reviewRequestedMergeRequests(
                    state: opened, approved: false, updatedAfter: $activeReviewsAfter
                  ) {
                    count
                  }
                }
              }
              headPipeline {
                path
                startedAt
                finishedAt
                status
                failureReason
                runningJobs: jobs(statuses: RUNNING, retried: false) {
                  count
                }
                firstRunningJob: jobs(statuses: RUNNING, first: 1, retried: false) {
                  nodes {
                    webPath
                  }
                }
                failedJobs: jobs(statuses: FAILED, retried: false) {
                  count
                  nodes {
                    name
                  }
                }
                failedJobTraces: jobs(statuses: FAILED, first: 1, retried: false) {
                  nodes {
                    name
                    trace { htmlSummary }
                  }
                }
              }
            }
          }
        }
      }

      #{CORE_USER_FRAGMENT}
      #{EXT_USER_FRAGMENT}
      #{CORE_MERGE_REQUEST_FRAGMENT}
    GRAPHQL

    response = client.query(merge_requests_graphql_query, username: username, activeReviewsAfter: 7.days.ago)

    OpenStruct.new(
      user: make_serializable(response.data.user),
      updated_at: Time.current
    )
  end

  def fetch_merged_merge_requests(username)
    merge_requests_graphql_query = <<-GRAPHQL
      query($username: String!) {
        user(username: $username) {
          mergedMergeRequests: authoredMergeRequests(state: merged, sort: MERGED_AT_DESC, first: 20) {
            nodes {
              iid
              ...CoreMergeRequestFields
              mergedAt
              mergeUser {
                ...ExtendedUserFields
              }
            }
          }
        }
      }

      #{CORE_USER_FRAGMENT}
      #{EXT_USER_FRAGMENT}
      #{CORE_MERGE_REQUEST_FRAGMENT}
    GRAPHQL

    response = client.query(merge_requests_graphql_query, username: username)

    OpenStruct.new(
      user: make_serializable(response.data.user),
      updated_at: Time.current
    )
  end

  def fetch_issues(merged_mr_issue_iids, open_mr_issue_iids)
    query = <<-GRAPHQL
      query($projectPath : ID!, $issueIids: [String!], $openIssueIids: [String!]) {
        project(fullPath: $projectPath) {
          issues(iids: $issueIids) {
            nodes { ...CoreIssueFields }
          }
          openIssues: issues(iids: $openIssueIids, state: opened) {
            nodes { ...CoreIssueFields }
          }
        }
      }

      #{CORE_ISSUE_FRAGMENT}
    GRAPHQL

    response = client.query(
      query,
      projectPath: "gitlab-org/gitlab",
      issueIids: open_mr_issue_iids,
      openIssueIids: merged_mr_issue_iids # Only fetch open issues for merged MRs
    )

    project = make_serializable(response.data.project)
    project.issues.nodes + project.openIssues.nodes
  end

  def make_serializable(obj)
    # GraphQL types cannot be serialized, so we work around that by reparsing from JSON into anonymous objects
    JSON.parse!(obj.to_json, object_class: OpenStruct)
  end

  def convert_mr_pipeline(pipeline)
    return unless pipeline

    failed_jobs = pipeline.failedJobs

    pipeline.startedAt = parse_graphql_time(pipeline.startedAt)
    pipeline.finishedAt = parse_graphql_time(pipeline.finishedAt)

    pipeline.webUrl =
      if pipeline.path
        web_path = pipeline.path

        # Try to make the user land in the most contextual page possible, depending on the state of the pipeline
        if failed_jobs.count.positive?
          web_path += "/failures"
        elsif pipeline.status == "RUNNING"
          running_jobs = pipeline.firstRunningJob.nodes
          web_path = pipeline.runningJobs.count == 1 ? running_jobs.first.webPath : "#{web_path}/builds"
          pipeline.summary = "#{helpers.pluralize(pipeline.runningJobs.count, "job")} still running"
        end

        make_full_url(web_path)
      end

    tag = view_context.tag
    header = "#{helpers.pluralize(failed_jobs.count, "job")} #{helpers.pluralize_without_count(failed_jobs.count, "has", "have")} failed in the pipeline:<br/><br/>"
    pipeline.failureSummary =
      if failed_jobs.count == 1
        failed_job_trace = pipeline.failedJobTraces.nodes.first

        <<~HTML
          #{header}
          #{tag.code(failed_job_trace.name, escape: false)}:
          <br/>
          #{failed_job_trace.trace.htmlSummary}
        HTML
      elsif failed_jobs.count.positive?
        <<~HTML
          #{header}
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
        row: row_class(mr),
        pipeline: pipeline_class(mr),
        mergeStatus: merge_status_class(mr)
      }

      convert_mr_pipeline(mr.headPipeline)

      mr.detailedMergeStatus = humanized_enum(mr.detailedMergeStatus.sub("STATUS", ""))
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

      mr.bootstrapClass = {
        row: mr.contextualLabels.any? ? "primary" : "secondary",
        mergeStatus: "primary"
      }

      mr.labels.nodes.each do |label|
        label.bootstrapClass =
          if label.title.start_with?("workflow::")
            [
              "bg-#{WORKFLOW_LABELS_BS_CLASS.fetch(label.title, "secondary")}",
              "text-light"
            ]
          else
            []
          end
        label.title.delete_prefix!("workflow::")
      end
    end
  end

  def parse_response(response)
    return unless response

    @updated_at = response.updated_at
    @next_update =
      Rails.application.config.action_controller.perform_caching ? MR_CACHE_VALIDITY.after(response.updated_at) : nil
    open_mrs = response.user.openMergeRequests.nodes
    merged_mrs = response.user.mergedMergeRequests.nodes

    @open_issues_by_iid = issues_from_merge_requests(open_mrs, merged_mrs)
    @open_merge_requests = open_mrs.map { |mr| convert_open_merge_request(mr) }
    @merged_merge_requests = merged_merge_requests(merged_mrs).map { |mr| convert_merged_merge_request(mr) }
  end

  def authored_mr_lists_cache_key(user)
    "merge_requests_v2/authored_list/#{user_hash(user)}"
  end

  def last_authored_mr_lists_cache_key(user)
    "merge_requests_v2/authored_list/#{user_hash(user)}/last"
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

  def row_class(mr)
    return "warning" if mr.conflicts
    return "secondary" if mr.detailedMergeStatus == "BLOCKED_STATUS"
    return "info" if mr.reviewers.nodes.any? { |reviewer| reviewer.mergeRequestInteraction.reviewState == "REVIEWED" }

    merge_status_class(mr)
  end

  def merge_status_class(mr)
    MERGE_STATUS_BS_CLASS.fetch(mr.detailedMergeStatus, "secondary")
  end

  def pipeline_class(mr)
    PIPELINE_BS_CLASS.fetch(mr.headPipeline&.status, "secondary")
  end

  def user_activity_icon_class(user)
    %w[fa-solid fa-moon] if user.lastActivityOn < 1.day.ago
  end

  def review_icon_class(reviewer)
    REVIEW_ICON[reviewer.mergeRequestInteraction.reviewState]
  end

  def review_text_class(reviewer)
    REVIEW_TEXT_BS_CLASS[reviewer.mergeRequestInteraction.reviewState]
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

    Rails.cache.fetch("issues_v2/open/#{issue_iids.join("-")}", expires_in: MR_CACHE_VALIDITY) do
      fetch_issues(merged_mr_issue_iids, open_mr_issue_iids)
    end&.to_h { |issue| [issue.iid, issue] }
  end

  def merged_merge_requests(merge_requests)
    return unless @open_issues_by_iid

    open_mr_issue_iids = @open_issues_by_iid.keys
    merged_request_issue_iids = merge_request_issue_iids(merge_requests)

    merge_requests.filter do |mr|
      open_mr_issue_iids.include?(merged_request_issue_iids[mr.iid]) ||
        mr.mergedAt >= 2.days.ago
    end
  end
end
