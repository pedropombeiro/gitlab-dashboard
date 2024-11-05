# frozen_string_literal: true

require "ostruct"

class MergeRequestsController < ApplicationController
  MR_ISSUE_PATTERN = %r{[^\d]*(?<issue_id>\d+)[/-].+}i.freeze

  PIPELINE_BS_CLASS = { "SUCCESS" => "success", "FAILED" => "danger", "RUNNING" => "primary" }.freeze
  MERGE_STATUS_BS_CLASS = { "BLOCKED_STATUS" => "warning", "CI_STILL_RUNNING" => "primary" }.freeze
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
  WORKFLOW_LABELS = WORKFLOW_LABELS_BS_CLASS.keys

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
    response = Rails.cache.fetch(authored_mr_lists_cache_key(assignee), expires_in: 5.minutes) do
      mrs = fetch_merge_requests(assignee)
      Rails.cache.write(last_authored_mr_lists_cache_key(assignee), mrs)
      mrs
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
    response = Rails.cache.fetch("user_info_v2/#{user_hash(username)}", expires_in: 1.day) do
      response = client.query <<-GRAPHQL
        query {
          user: #{username ? "user(username: \"#{username}\")" : "currentUser"} {
            username
            avatarUrl
            webUrl
          }
        }
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

  def fetch_merge_requests(username)
    merge_requests_graphql_query = <<-GRAPHQL
      query {
        user: #{username ? "user(username: \"#{username}\")" : "currentUser"} {
          openMergeRequests: authoredMergeRequests(state: opened, sort: UPDATED_DESC) {
            nodes {
              ...CoreMergeRequestFields
              updatedAt
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
                  ...CoreUserFields
                  mergeRequestInteraction {
                    approved
                    reviewState
                  }
                }
              }
              headPipeline {
                path
                status
                startedAt
                finishedAt
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
              }
            }
          }
          mergedMergeRequests: authoredMergeRequests(
            state: merged
            sort: MERGED_AT_DESC
            first: 20
          ) {
            nodes {
              iid
              ...CoreMergeRequestFields
              mergedAt
              mergeUser {
                ...CoreUserFields
              }
            }
          }
        }
      }

      fragment CoreUserFields on User {
        username
        avatarUrl
        webUrl
        lastActivityOn
        location
        status {
          availability
          messageHtml
        }
      }

      fragment CoreMergeRequestFields on MergeRequest {
        iid
        reference
        webUrl
        titleHtml
        sourceBranch
        targetBranch
        createdAt
        assignees {
          nodes {
            avatarUrl
            webUrl
          }
        }
        labels {
          nodes { title }
        }
      }
    GRAPHQL

    response = client.query(merge_requests_graphql_query)

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

      fragment CoreIssueFields on Issue {
        iid
        webUrl
        titleHtml
      }
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

  def parse_response(response)
    return unless response

    @updated_at = response.updated_at

    @open_issues_by_iid =
      issues_from_merge_requests(response.user.openMergeRequests.nodes, response.user.mergedMergeRequests.nodes)

    @open_merge_requests = response.user.openMergeRequests.nodes.map do |mr|
      mr.bootstrapClass = {
        row: row_class(mr),
        pipeline: pipeline_class(mr),
        mergeStatus: merge_status_class(mr)
      }
      mr.createdAt = parse_graphql_time(mr.createdAt)
      mr.updatedAt = parse_graphql_time(mr.updatedAt)
      mr.issue = issue_from_mr(mr)

      if mr.headPipeline
        failed_jobs = mr.headPipeline.failedJobs

        mr.headPipeline.startedAt = parse_graphql_time(mr.headPipeline.startedAt)
        mr.headPipeline.finishedAt = parse_graphql_time(mr.headPipeline.finishedAt)

        mr.headPipeline.webUrl =
          if mr.headPipeline.path
            web_path = mr.headPipeline.path

            # Try to make the user land in the most contextual page possible, depending on the state of the pipeline
            if failed_jobs.count.positive?
              web_path += "/failures"
            elsif mr.headPipeline.status == "RUNNING"
              running_jobs = mr.headPipeline.firstRunningJob.nodes
              web_path = mr.headPipeline.runningJobs.count == 1 ? running_jobs.first.webPath : "#{web_path}/builds"
              mr.headPipeline.summary =
                <<~HTML
                  #{helpers.pluralize(mr.headPipeline.runningJobs.count, "job")} still running
                HTML
            end

            make_full_url(web_path)
          end

        tag = view_context.tag
        mr.headPipeline.failureSummary =
          if failed_jobs.count.positive?
            <<~HTML
            #{helpers.pluralize(failed_jobs.count, "job")} #{helpers.pluralize_without_count(failed_jobs.count, "has", "have")} failed in the pipeline:<br/><br/>
            #{tag.ul(failed_jobs.nodes.map { |j| tag.li(tag.code(j.name)) }.join, escape: false)}
            HTML
          else
            nil
          end
        mr.headPipeline.summary ||= mr.headPipeline.failureSummary if mr.headPipeline.status == "FAILED"
      end

      mr.detailedMergeStatus = humanized_enum(mr.detailedMergeStatus.sub("STATUS", ""))
      mr.reviewers.nodes.each do |reviewer|
        reviewer.lastActivityOn = parse_graphql_time(reviewer.lastActivityOn)
        reviewer.review = reviewer.mergeRequestInteraction.reviewState
        reviewer.bootstrapClass = {
          text: review_text_class(reviewer),
          icon: review_icon_class(reviewer),
          activity_icon: user_activity_icon_class(reviewer)
        }.compact
      end

      mr.labels.nodes.filter! { |label| label.title.start_with?("pipeline::") }

      mr
    end

    @merged_merge_requests = merged_merge_requests(response.user.mergedMergeRequests.nodes).filter_map do |mr|
      mr.labels.nodes.filter! do |label|
        WORKFLOW_LABELS.any? { |prefix| label.title.start_with?(prefix) }
      end
      workflow_label = mr.labels.nodes.first&.title
      mr.workflowLabel = workflow_label&.delete_prefix("workflow::")
      mr.issue = issue_from_mr(mr)

      mr.bootstrapClass = {
        row: mr.labels.nodes.any? ? "primary" : "secondary",
        mergeStatus: "primary",
        label: "bg-#{WORKFLOW_LABELS_BS_CLASS.fetch(workflow_label, "secondary")} text-light"
      }
      mr.createdAt = parse_graphql_time(mr.createdAt)
      mr.mergedAt = parse_graphql_time(mr.mergedAt)
      mr.mergeUser.lastActivityOn = parse_graphql_time(mr.mergeUser.lastActivityOn)

      mr
    end
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
      .filter_map { |title, value| value&.present? ? tag.div("#{tag.b(title)}: #{value}", class: "text-start", escape: false) : nil }
      .join
  end

  def user_help_title(user)
    tooltip_from_hash(
      "Location": user.location,
      "Last activity": user.lastActivityOn > 1.day.ago ? "today" : "#{helpers.time_ago_in_words(user.lastActivityOn)} ago",
      "Message": user.status&.messageHtml
    )
  end

  def reviewer_help_title(reviewer)
    tooltip_from_hash(
      "State": humanized_enum(reviewer.mergeRequestInteraction.reviewState),
      "Location": reviewer.location,
      "Last activity": reviewer.lastActivityOn > 1.day.ago ? "today" : "#{helpers.time_ago_in_words(reviewer.lastActivityOn)} ago",
      "Message": reviewer.status&.messageHtml
    )
  end

  def row_class(mr)
    return "warning" if mr.conflicts
    return "secondary" if mr.detailedMergeStatus == "BLOCKED_STATUS"
    return "info" if mr.reviewers&.nodes&.any? { |reviewer| reviewer.mergeRequestInteraction.reviewState == "REVIEWED" }

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

    response = Rails.cache.fetch("issues_v2/open/#{issue_iids.join("-")}", expires_in: 5.minutes) do
      fetch_issues(merged_mr_issue_iids, open_mr_issue_iids)
    end

    return unless response

    response.to_h { |issue| [issue.iid, issue] }
  end

  def merged_merge_requests(merge_requests)
    return unless @open_issues_by_iid

    open_mr_issue_iids = @open_issues_by_iid.keys
    merged_request_issue_iids = merge_request_issue_iids(merge_requests)

    merge_requests.filter { |mr| open_mr_issue_iids.include?(merged_request_issue_iids[mr.iid]) }
  end
end
