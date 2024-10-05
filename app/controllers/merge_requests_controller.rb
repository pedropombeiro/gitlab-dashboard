class MergeRequestsController < ApplicationController
  STATUS_ALIASES = { "SUCCESS" => "success", "FAILED" => "danger", "RUNNING" => "active" }.freeze
  MERGE_STATUS_ALIASES = { "BLOCKED_STATUS" => "warning", "CI_STILL_RUNNING" => "active" }.freeze

  def index
    json = Rails.cache.read("authored_merge_requests")
    @authored_merge_requests = json ? JSON.parse!(json) : nil

    unless @authored_merge_requests
      json = fetch_merge_requests.to_json
      @authored_merge_requests = JSON.parse(json)
      Rails.cache.write("authored_merge_requests", json)
    end

    @authored_merge_requests = @authored_merge_requests.map do |mr|
      mr.deep_merge({
        "bootstrapClass" => {
          "pipeline" => STATUS_ALIASES.fetch(mr["headPipeline"]["status"], "primary"),
          "mergeStatus" => MERGE_STATUS_ALIASES.fetch(mr["detailedMergeStatus"], "primary")
        },
        "headPipeline" => {
          "status" => mr["headPipeline"]["status"].capitalize
        },
        "detailedMergeStatus" => mr["detailedMergeStatus"].sub("STATUS", "").tr("_", " ").capitalize
      })
    end
  end

  private

  def authorization
    "Bearer #{ENV["GITLAB_TOKEN"]}"
  end

  def client
    ::Graphlient::Client.new(
      "https://gitlab.com/api/graphql",
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
                  username
                  webUrl
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

    response.data.current_user.authored_merge_requests.nodes
  end
end
