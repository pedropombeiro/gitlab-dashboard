# frozen_string_literal: true

require "ostruct"

class MergeRequestsController < ApplicationController
  include ActionView::Helpers::DateHelper

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

  helper_method :humanized_duration, :humanized_enum, :make_full_url, :reviewer_help_title

  def index
    assignee = params[:assignee]
    json = Rails.cache.fetch("merge_requests_v1/authored_list/#{assignee}", expires_in: 5.minutes) do
      fetch_merge_requests(assignee).to_json
    end

    response = json ? JSON.parse!(json, object_class: OpenStruct) : nil

    @user = response.user
    return render_404 unless @user

    @updated_at = Time.parse(response.updatedAt)
    @open_merge_requests = response.user.openMergeRequests.nodes.map do |mr|
      mr.bootstrapClass = {
        row: row_class(mr),
        pipeline: pipeline_class(mr),
        mergeStatus: merge_status_class(mr)
      }
      mr.createdAt = Time.parse(mr.createdAt)
      mr.updatedAt = Time.parse(mr.updatedAt) if mr.updatedAt
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
          activity_icon: reviewer_activity_icon_class(reviewer)
        }.compact
      end

      mr.labels.nodes.filter! do |label| label.title.start_with?("pipeline::") end

      mr
    end
  end

  private

  def render_404
    respond_to do |format|
      format.html { render file: "#{Rails.root}/public/404.html", layout: false, status: :not_found }
      format.xml  { head :not_found }
      format.any  { head :not_found }
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
    response = client.query <<~GRAPHQL
      query {
        user: #{username ? "user(username: \"#{username}\")" : "currentUser"} {
          username
          webUrl
          avatarUrl
          openMergeRequests: authoredMergeRequests(state: opened, sort: UPDATED_DESC) {
            nodes {
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

    {
      user: response.data.user,
      updatedAt: Time.current
    }
  end

  def make_full_url(path)
    return path if path.nil? || path.start_with?("http")

    "#{gitlab_instance_url}#{path}"
  end

  def humanized_enum(value)
    value.tr("_", " ").capitalize.sub("Ci ", "CI ").strip
  end

  def humanized_duration(seconds, most_significant_only: false)
    parts = ActiveSupport::Duration.build(seconds).parts.except(:seconds)
    parts = parts.take(1) if most_significant_only
    duration = parts.reduce("") { |output, (key, val)| output += "#{val}#{key.to_s.first} " }.strip

    return "just now" if duration.blank?

    "#{duration} ago"
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
    return "info" if mr.reviewers.nodes.any? { |reviewer| reviewer.mergeRequestInteraction.reviewState == "REVIEWED" }

    merge_status_class(mr)
  end

  def merge_status_class(mr)
    MERGE_STATUS_BS_CLASS.fetch(mr.detailedMergeStatus, "secondary")
  end

  def pipeline_class(mr)
    PIPELINE_BS_CLASS.fetch(mr.headPipeline&.status, "secondary")
  end

  def reviewer_activity_icon_class(reviewer)
    "fa-solid fa-moon" if Time.current - reviewer.lastActivityOn >= 1.day
  end

  def review_icon_class(reviewer)
    REVIEW_ICON[reviewer.mergeRequestInteraction.reviewState]
  end

  def review_text_class(reviewer)
    REVIEW_TEXT_BS_CLASS[reviewer.mergeRequestInteraction.reviewState]
  end
end
