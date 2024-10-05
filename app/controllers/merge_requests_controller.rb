class MergeRequestsController < ApplicationController
  STATUS_ALIASES = { "SUCCESS" => "success", "FAILED" => "danger", "RUNNING" => "active" }.freeze
  MERGE_STATUS_ALIASES = { "BLOCKED_STATUS" => "warning", "CI_STILL_RUNNING" => "active" }.freeze
  REVIEW_ICON = {
    "UNREVIEWED" => "fa-solid fa-hourglass-start",
    "REVIEWED" => "fa-solid fa-check",
    "REQUESTED_CHANGES" => "fa-solid fa-ban",
    "APPROVED" => "fa-regular fa-thumbs-up",
    "UNAPPROVED" => "fa-solid fa-arrow-rotate-left",
    "REVIEW_STARTED" => "fa-solid fa-hourglass-half"
  }.freeze
  REVIEW_TEXT = {
    "UNREVIEWED" => "dark",
    "REVIEWED" => "secondary",
    "REQUESTED_CHANGES" => "danger",
    "APPROVED" => "success",
    "UNAPPROVED" => "info",
    "REVIEW_STARTED" => "info"
  }.freeze

  helper_method :humanized_duration, :humanized_enum, :make_full_url

  def index
    json = Rails.cache.fetch("merge_requests_v1/authored_list", expires_in: 5.minutes) do
      fetch_merge_requests.to_json
    end

    response = json ? JSON.parse!(json, symbolize_names: true) : nil

    @current_user = response[:currentUser]
    @updated_at = Time.parse(response[:updatedAt])
    @authored_merge_requests = response.dig(*%i[currentUser authoredMergeRequests nodes]).map do |mr|
      mr.deep_merge({
        bootstrapClass: {
          pipeline: STATUS_ALIASES.fetch(mr.dig(*%i[headPipeline status]), "primary"),
          mergeStatus: MERGE_STATUS_ALIASES.fetch(mr[:detailedMergeStatus], "primary")
        },
        headPipeline: {
          status: mr.dig(*%i[headPipeline status]).capitalize
        },
        reviewers: {
          nodes: mr.dig(*%i[reviewers nodes]).map do |reviewer|
            reviewer.deep_merge(
              bootstrapClass: {
                icon: review_icon_class(reviewer),
                text: review_text_class(reviewer)
              },
              review: reviewer.dig(*%i[mergeRequestInteraction reviewState]),
            )
          end
        },
        detailedMergeStatus: humanized_enum(mr[:detailedMergeStatus].sub("STATUS", ""))
      })
    end
  end

  private

  def gitlab_instance_url
    "https://gitlab.com"
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

  def fetch_merge_requests
    response = client.query <<~GRAPHQL
      query {
        currentUser {
          username
          webUrl
          avatarUrl
          authoredMergeRequests(state: opened, sort: UPDATED_DESC) {
            nodes {
              reference
              webUrl
              titleHtml
              sourceBranch
              createdAt
              updatedAt
              approved
              approvalsRequired
              approvalsLeft
              autoMergeEnabled
              detailedMergeStatus
              squashOnMerge
              conflicts
              reviewers {
                nodes {
                  avatarUrl
                  username
                  webUrl
                  lastActivityOn
                  location
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
                failedJobs: jobs(statuses: FAILED, retried: false) {
                  count
                }
              }
            }
          }
        }
      }
    GRAPHQL

    {
      currentUser: response.data.current_user,
      updatedAt: Time.current
    }
  end

  def make_full_url(path)
    return path if path.start_with?("http")

    "#{gitlab_instance_url}#{path}"
  end

  def humanized_enum(value)
    value.tr("_", " ").capitalize
  end

  def humanized_duration(seconds)
    ActiveSupport::Duration.build(seconds).parts.except(:seconds)
      .reduce("") { |output, (key, val)| output += "#{val}#{key.to_s.first} " }
      .strip
  end

  def review_icon_class(reviewer)
    REVIEW_ICON[reviewer.dig(*%i[mergeRequestInteraction reviewState])]
  end

  def review_text_class(reviewer)
    REVIEW_TEXT[reviewer.dig(*%i[mergeRequestInteraction reviewState])]
  end
end
