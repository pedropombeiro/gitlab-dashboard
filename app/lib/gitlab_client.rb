# frozen_string_literal: true

require "ostruct"

class GitlabClient
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

  CORE_LABEL_FRAGMENT = <<-GRAPHQL
    fragment CoreLabelFields on Label {
      title
      descriptionHtml
      color
      textColor
    }
  GRAPHQL

  CORE_ISSUE_FRAGMENT = <<-GRAPHQL
    fragment CoreIssueFields on Issue {
      iid
      webUrl
      titleHtml
      labels {
        nodes { ...CoreLabelFields }
      }
    }
  GRAPHQL

  CORE_MERGE_REQUEST_FRAGMENT = <<-GRAPHQL
    fragment CoreMergeRequestFields on MergeRequest {
      iid
      webUrl
      titleHtml
      project { fullPath }
      reference
      sourceBranch
      targetBranch
      createdAt
      updatedAt
      assignees {
        nodes { ...CoreUserFields }
      }
      labels {
        nodes { ...CoreLabelFields }
      }
    }
  GRAPHQL

  def self.gitlab_instance_url
    @gitlab_instance_url ||= ENV.fetch("GITLAB_URL", "https://gitlab.com")
  end

  def make_full_url(path)
    return path if path.nil? || path.start_with?("http")

    "#{self.class.gitlab_instance_url}#{path}"
  end

  def fetch_user(username)
    response = self.class.client.query <<-GRAPHQL
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
                  iid
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
                finishedJobs: jobs(statuses: [SUCCESS, FAILED, CANCELED, SKIPPED, MANUAL], retried: false) {
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
                failedJobTraces: jobs(statuses: FAILED, first: 2, retried: false) {
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
      #{CORE_LABEL_FRAGMENT}
      #{CORE_MERGE_REQUEST_FRAGMENT}
    GRAPHQL

    response = self.class.client.query(merge_requests_graphql_query, username: username, activeReviewsAfter: 7.days.ago)

    OpenStruct.new(
      user: make_serializable(response.data.user),
      updated_at: Time.current
    )
  end

  def fetch_merged_merge_requests(username)
    merge_requests_graphql_query = <<-GRAPHQL
      query($username: String!) {
        user(username: $username) {
          firstCreatedMergedMergeRequests: authoredMergeRequests(state: merged, sort: CREATED_ASC, first: 1) {
            nodes {
              createdAt
            }
          }
          allMergedMergeRequests: authoredMergeRequests(state: merged) {
            count
            totalTimeToMerge
          }
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
      #{CORE_LABEL_FRAGMENT}
      #{CORE_MERGE_REQUEST_FRAGMENT}
    GRAPHQL

    response = self.class.client.query(merge_requests_graphql_query, username: username)

    OpenStruct.new(
      user: make_serializable(response.data.user),
      updated_at: Time.current
    )
  end

  # Fetches a list of issues given 2 lists of MRs, represented by a hash of { project_full_path:, issue_iid: }
  def fetch_issues(merged_mr_issue_iids, open_mr_issue_iids)
    issue_iids = (open_mr_issue_iids + merged_mr_issue_iids).filter { |h| h[:issue_iid] }.uniq
    project_full_paths = issue_iids.pluck(:project_full_path).uniq

    project_queries =
      project_full_paths.map.each_with_index do |project_full_path, index|
        project_issue_iids = issue_iids.filter_map do |h|
          (h[:project_full_path] == project_full_path) ? quote(h[:issue_iid]) : nil
        end.join(", ")

        <<-GRAPHQL
          project_#{index}: project(fullPath: "#{project_full_path}") {
            issues(iids: [#{project_issue_iids}]) {
              nodes { ...CoreIssueFields }
            }
          }
        GRAPHQL
      end.join("\n")

    query = <<-GRAPHQL
      query {
        #{project_queries}
      }

      #{CORE_LABEL_FRAGMENT}
      #{CORE_ISSUE_FRAGMENT}
    GRAPHQL

    response = self.class.client.query(query)
    data = make_serializable(response.data)

    project_full_paths.map.each_with_index do |_, index|
      data.public_send(:"project_#{index}").issues.nodes
    end.flatten
  end

  def self.client
    @client ||= ::Graphlient::Client.new(
      "#{gitlab_instance_url}/api/graphql",
      headers: {"Authorization" => authorization},
      http_options: {
        read_timeout: 20,
        write_timeout: 30
      }
    )
  end

  private

  def make_serializable(obj)
    # GraphQL types cannot be serialized, so we work around that by reparsing from JSON into anonymous objects
    JSON.parse!(obj.to_json, object_class: OpenStruct)
  end

  def quote(s)
    %("#{s}") if s
  end

  private_class_method def self.authorization
    "Bearer #{Rails.application.credentials.gitlab_token}"
  end
end
