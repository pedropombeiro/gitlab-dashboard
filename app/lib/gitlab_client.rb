# frozen_string_literal: true

require "async"
require "ostruct"

class GitlabClient
  include Honeybadger::InstrumentationHelper

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
        emoji
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
      project {
        fullPath
        webUrl
        avatarUrl
      }
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

  MONTHLY_MERGE_REQUEST_STATS_FRAGMENT = <<-GRAPHQL
    fragment MonthlyMergeRequestStatsFields on MergeRequestConnection {
      count
      totalTimeToMerge
    }
  GRAPHQL

  USER_QUERY = <<-GRAPHQL
    query($username: String!) {
      user(username: $username) {
        ...CoreUserFields
      }
    }

    #{CORE_USER_FRAGMENT}
  GRAPHQL

  CURRENT_USER_QUERY = <<-GRAPHQL
    query {
      user: currentUser {
        ...CoreUserFields
      }
    }

    #{CORE_USER_FRAGMENT}
  GRAPHQL

  OPEN_MERGE_REQUESTS_GRAPHQL_QUERY = <<-GRAPHQL
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
              finishedJobs: jobs(statuses: [SUCCESS, FAILED, CANCELED, SKIPPED, MANUAL], retried: false) {
                count
              }
              runningJobs: jobs(statuses: RUNNING, first: 1, retried: false) {
                count
                nodes {
                  webPath
                }
              }
              failedJobs: jobs(statuses: FAILED, retried: false) {
                count
                nodes {
                  name
                  allowFailure
                }
              }
              failedJobTraces: jobs(statuses: FAILED, first: 2, retried: false) {
                nodes {
                  name
                  trace { htmlSummary }
                  webPath
                  downstreamPipeline {
                    jobs(statuses: FAILED, first: 1) {
                      nodes {
                        webPath
                      }
                    }
                  }
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

  MERGED_MERGE_REQUESTS_GRAPHQL_QUERY = <<-GRAPHQL
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

  def self.gitlab_instance_url
    @gitlab_instance_url ||= ENV.fetch("GITLAB_URL", "https://gitlab.com")
  end

  def make_full_url(path)
    return path if path.nil? || path.start_with?("http")

    "#{self.class.gitlab_instance_url}#{path}"
  end

  def fetch_user(username, format: :open_struct)
    return format_response(format) { execute_query(USER_QUERY, "user", username: username) } if username.present?

    format_response(format) { execute_query(CURRENT_USER_QUERY, "user") }
  end

  def fetch_open_merge_requests(username, format: :open_struct)
    format_response(format) do
      execute_query(
        OPEN_MERGE_REQUESTS_GRAPHQL_QUERY,
        "open_merge_requests",
        username: username,
        activeReviewsAfter: 7.days.ago
      )
    end
  end

  def fetch_merged_merge_requests(username, format: :open_struct)
    format_response(format) do
      execute_query(MERGED_MERGE_REQUESTS_GRAPHQL_QUERY, "merged_merge_requests", username: username)
    end
  end

  def fetch_monthly_merged_merge_requests(username, format: :open_struct)
    monthly_merge_requests_graphql_queries = 12.times.map do |offset|
      bom = Time.current.beginning_of_month - offset.months
      eom = 1.month.after(bom)

      <<-GRAPHQL
        query($username: String!) {
          user(username: $username) {
            monthlyMergedMergeRequests#{offset}: authoredMergeRequests(
              state: merged,
              mergedAfter: "#{bom.to_fs}",
              mergedBefore: "#{eom.to_fs}") {
              ...MonthlyMergeRequestStatsFields
            }
          }
        }

        #{MONTHLY_MERGE_REQUEST_STATS_FRAGMENT}
      GRAPHQL
    end

    format_response(format) do
      results = Async do
        monthly_merge_requests_graphql_queries.map do |query|
          Async do
            make_serializable(execute_query(query, "monthly_merged_merge_requests", username: username))
          end
        end.map(&:wait)
      end.wait

      results.first.tap do |final_result|
        results[1..].each do |monthly_result|
          monthly_result.data.user.table.keys.each do |k|
            final_result.data.user[k] = monthly_result.data.user[k]
          end
        end
      end
    end
  end

  # Fetches a list of issues given 2 lists of MRs, represented by a hash of { project_full_path:, issue_iid: }
  def fetch_issues(merged_mr_issue_iids, open_mr_issue_iids, format: :open_struct)
    issue_iids = (open_mr_issue_iids + merged_mr_issue_iids).filter { |h| h[:issue_iid] }.uniq
    project_full_paths = issue_iids.pluck(:project_full_path).uniq

    response = format_response(format) do
      results = Async do
        project_queries =
          project_full_paths.map.each_with_index do |project_full_path, index|
            project_issue_iids = issue_iids.filter_map do |h|
              (h[:project_full_path] == project_full_path) ? h[:issue_iid] : nil
            end

            query = <<-GRAPHQL
              query($projectFullPath: ID!, $issueIids: [String!]) {
                project_#{index}: project(fullPath: $projectFullPath) {
                  issues(iids: $issueIids) {
                    nodes { ...CoreIssueFields }
                  }
                }
              }

              #{CORE_LABEL_FRAGMENT}
              #{CORE_ISSUE_FRAGMENT}
            GRAPHQL

            Async do
              make_serializable(execute_query(
                query, "issues",
                projectFullPath: project_full_path,
                issueIids: project_issue_iids))
            end
          end

        project_queries.map(&:wait)
      end.wait

      results.first.tap do |final_result|
        results[1..].each do |project_result|
          project_result.data.table.keys.each do |k|
            final_result.data[k] = project_result.data[k]
          end
        end
      end
    end

    return response unless format == :open_struct

    data = response.response.data
    response.response.data = project_full_paths.map.each_with_index do |_, index|
      data.public_send(:"project_#{index}").issues.nodes
    end.flatten

    response
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

  def execute_query(query, name, **args)
    Rails.logger.debug { %(Executing "#{name}" GraphQL query (args: #{args})...) }

    metric_source "graphql_metrics"
    metric_attributes(name: name, **args.slice(:username))

    increment_counter "graphql.query.count"

    result = nil
    histogram "graphql.query.duration" do
      result = self.class.client.query(query, **args)
    end

    result
  end

  def format_response(format)
    request_duration, response = monotonic_timer { yield }

    case format
    when :yaml_fixture
      JSON.parse(response.to_json).to_yaml
    else
      OpenStruct.new(
        response: make_serializable(response),
        updated_at: Time.current,
        request_duration: request_duration.round(1)
      )
    end
  end

  def make_serializable(obj)
    return obj if obj.is_a?(OpenStruct)

    # GraphQL types cannot be serialized, so we work around that by reparsing from JSON into anonymous objects
    JSON.parse!(obj.to_json, object_class: OpenStruct)
  end

  # returns two parameters, the first is the duration of the execution, and the second is
  # the return value of the passed block
  def monotonic_timer
    start_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    result = yield
    finish_time = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
    [(finish_time - start_time).seconds, result]
  end

  private_class_method def self.authorization
    "Bearer #{Rails.application.credentials.gitlab_token}"
  end
end
