# frozen_string_literal: true

require "ostruct"

class MergeRequestsController < ApplicationController
  include ActionView::Helpers::DateHelper

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
    assignee = fetch_username(params[:assignee])

    unless assignee
      return render(status: :network_authentication_required, plain: "Please configure GITLAB_TOKEN to use default user")
    end

    json = Rails.cache.fetch("merge_requests_v1/authored_list/#{assignee}", expires_in: 5.minutes) do
      fetch_merge_requests(assignee).to_json
    end

    response = json ? JSON.parse!(json, object_class: OpenStruct) : nil

    @user = response.user
    return render_404 unless @user

    @updated_at = Time.parse(response.updatedAt)

    @open_issues_by_iid =
      open_issues_from_merge_requests(response.user.openMergeRequests.nodes + response.user.mergedMergeRequests.nodes)

    @open_merge_requests = response.user.openMergeRequests.nodes.map do |mr|
      mr.bootstrapClass = {
        row: row_class(mr),
        pipeline: pipeline_class(mr),
        mergeStatus: merge_status_class(mr)
      }
      mr.createdAt = Time.parse(mr.createdAt) if mr.createdAt
      mr.updatedAt = Time.parse(mr.updatedAt) if mr.updatedAt
      mr.issue = issue_from_mr(mr)

      if mr.headPipeline
        mr.headPipeline.startedAt = Time.parse(mr.headPipeline.startedAt) if mr.headPipeline.startedAt
        mr.headPipeline.finishedAt = Time.parse(mr.headPipeline.finishedAt) if mr.headPipeline.finishedAt

        if mr.headPipeline&.path
          if mr.headPipeline.status == "FAILED"
            mr.headPipeline.webUrl = "#{make_full_url(mr.headPipeline.path)}/failures"
          else
            mr.headPipeline.webUrl = make_full_url(mr.headPipeline.path)
          end
        end
      end

      mr.detailedMergeStatus = humanized_enum(mr.detailedMergeStatus.sub("STATUS", ""))
      mr.reviewers.nodes.each do |reviewer|
        reviewer.lastActivityOn = Time.parse(reviewer.lastActivityOn) if reviewer.lastActivityOn
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
      mr.createdAt = Time.parse(mr.createdAt) if mr.createdAt
      mr.mergedAt = Time.parse(mr.mergedAt) if mr.mergedAt
      mr.mergeUser.lastActivityOn = Time.parse(mr.mergeUser.lastActivityOn) if mr.mergeUser.lastActivityOn

      mr
    end
  end

  private

  MERGE_REQUESTS_GRAPHQL_QUERY = <<-GRAPHQL
    query($username: String!) {
      user(username: $username) {
        username
        webUrl
        avatarUrl
        openMergeRequests: authoredMergeRequests(state: opened, sort: UPDATED_DESC) {
          nodes {
            iid
            reference
            webUrl
            titleHtml
            sourceBranch
            targetBranch
            createdAt
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
            assignees {
              nodes {
                avatarUrl
                webUrl
              }
            }
            reviewers {
              nodes {
                avatarUrl
                username
                webUrl
                lastActivityOn
                location
                status {
                  availability
                  messageHtml
                }
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
              failedJobs: jobs(statuses: FAILED, retried: false) {
                count
                nodes {
                  name
                }
              }
            }
            labels {
              nodes { title }
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
            reference
            webUrl
            titleHtml
            sourceBranch
            targetBranch
            createdAt
            mergedAt
            mergeUser {
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
        }
      }
    }
  GRAPHQL

  def fetch_username(username)
    username ||= Digest::SHA256.hexdigest(ENV["GITLAB_TOKEN"] || "Anonymous")[0..15]
    json = Rails.cache.fetch("user_info_v1/#{username}", expires_in: 1.day) do
      response = client.query <<~GRAPHQL
        query {
          currentUser { username }
        }
      GRAPHQL

      response.to_json
    end

    JSON.parse!(json, object_class: OpenStruct).data.currentUser&.username
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

  def fetch_merge_requests(username)
    response = client.query(MERGE_REQUESTS_GRAPHQL_QUERY, username: username)

    {
      user: response.data.user,
      updatedAt: Time.current
    }
  end

  def fetch_open_issues(iids)
    query = <<-GRAPHQL
      query($projectPath : ID!, $iids: [String!]) {
        project(fullPath: $projectPath) {
          issues(iids: $iids, state: opened) {
            nodes {
              iid
              webUrl
              titleHtml
            }
          }
        }
      }
    GRAPHQL

    client.query(query, projectPath: "gitlab-org/gitlab", iids: iids).data.project.issues.nodes
  end

  def make_full_url(path)
    return path if path.nil? || path.start_with?("http")

    "#{gitlab_instance_url}#{path}"
  end

  def humanized_enum(value)
    value.tr("_", " ").capitalize.sub("Ci ", "CI ").strip
  end

  def user_help_title(user)
    {
      "Location": user.location,
      "Last activity": Time.current - user.lastActivityOn < 1.day ? "today" : "#{time_ago_in_words(user.lastActivityOn)} ago",
      "Message": user.status&.messageHtml
    }.filter_map { |title, value| value&.present? ? "<div class=\"text-start\"><b>#{title}</b>: #{value}</div>" : nil }
      .join
  end

  def reviewer_help_title(reviewer)
    {
      "State": humanized_enum(reviewer.mergeRequestInteraction.reviewState),
      "Location": reviewer.location,
      "Last activity": Time.current - reviewer.lastActivityOn < 1.day ? "today" : "#{time_ago_in_words(reviewer.lastActivityOn)} ago",
      "Message": reviewer.status&.messageHtml
    }.filter_map { |title, value| value&.present? ? "<div class=\"text-start\"><b>#{title}</b>: #{value}</div>" : nil }
      .join
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
    "fa-solid fa-moon" if Time.current - user.lastActivityOn >= 1.day
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

  def open_issues_from_merge_requests(merge_requests)
    merged_request_issue_iids = merge_request_issue_iids(merge_requests)
    issue_iids = merged_request_issue_iids.values.compact.sort.uniq

    json = Rails.cache.fetch("issues_v1/open/#{issue_iids.join("-")}", expires_in: 5.minutes) do
      fetch_open_issues(issue_iids).to_json
    end

    return unless json

    JSON.parse!(json, object_class: OpenStruct).to_h { |issue| [issue.iid, issue] }
  end

  def merged_merge_requests(merge_requests)
    return unless @open_issues_by_iid

    open_issue_iids = @open_issues_by_iid.keys
    merged_request_issue_iids = merge_request_issue_iids(merge_requests)

    merge_requests.filter { |mr| open_issue_iids.include?(merged_request_issue_iids[mr.iid]) }
  end
end
