# frozen_string_literal: true

require "ostruct"

module GitlabApiConcern
  extend ActiveSupport::Concern

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

  def gitlab_instance_url
    @gitlab_instance_url ||= ENV.fetch("GITLAB_URL", "https://gitlab.com")
  end

  def fetch_user(username)
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
                jobs(retried: false) {
                  count
                }
                finishedJobs: jobs(statuses: [SUCCESS, FAILED, CANCELED, SKIPPED], retried: false) {
                  count
                }
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
                    webPath
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

  private

  def make_serializable(obj)
    # GraphQL types cannot be serialized, so we work around that by reparsing from JSON into anonymous objects
    JSON.parse!(obj.to_json, object_class: OpenStruct)
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
end