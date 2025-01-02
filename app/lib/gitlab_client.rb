# frozen_string_literal: true

require "async"
require "ostruct"

class GitlabClient
  include Honeybadger::InstrumentationHelper

  private_class_method def self.authorization
    "Bearer #{Rails.application.credentials.gitlab_token}"
  end

  def self.gitlab_instance_url
    @gitlab_instance_url ||= ENV.fetch("GITLAB_URL", "https://gitlab.com")
  end

  Client = ::Graphlient::Client.new(
    "#{gitlab_instance_url}/api/graphql",
    headers: {"Authorization" => authorization},
    http_options: {
      read_timeout: 30,
      write_timeout: 20
    },
    allow_dynamic_queries: false
  )

  # rubocop:disable Style/RedundantHeredocDelimiterQuotes -- we want to ensure we don't use interpolation
  CoreUserFragment = Client.parse <<-'GRAPHQL'
    fragment on User {
      username
      avatarUrl
      webUrl
    }
  GRAPHQL

  ExtendedUserFragment = Client.parse <<-'GRAPHQL'
    fragment on User {
      ...GitlabClient::CoreUserFragment
      lastActivityOn
      location
      status {
        availability
        emoji
        message
      }
    }
  GRAPHQL

  CoreLabelFragment = Client.parse <<-'GRAPHQL'
    fragment on Label {
      title
      descriptionHtml
      color
      textColor
    }
  GRAPHQL

  CoreIssueFragment = Client.parse <<-'GRAPHQL'
    fragment on Issue {
      iid
      webUrl
      titleHtml
      state
      labels {
        nodes { ...GitlabClient::CoreLabelFragment }
      }
    }
  GRAPHQL

  CoreMergeRequestFragment = Client.parse <<-'GRAPHQL'
    fragment on MergeRequest {
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
        nodes { ...GitlabClient::CoreUserFragment }
      }
      labels {
        nodes { ...GitlabClient::CoreLabelFragment }
      }
    }
  GRAPHQL

  MonthlyMergeRequestStatsFragment = Client.parse <<-'GRAPHQL'
    fragment on MergeRequestConnection {
      count
      totalTimeToMerge
    }
  GRAPHQL

  UserQuery = Client.parse <<-'GRAPHQL'
    query($username: String!) {
      user(username: $username) {
        ...GitlabClient::CoreUserFragment
      }
    }
  GRAPHQL

  CurrentUserQuery = Client.parse <<-'GRAPHQL'
    query {
      user: currentUser {
        ...GitlabClient::CoreUserFragment
      }
    }
  GRAPHQL

  ProjectIssuesQuery = Client.parse <<-'GRAPHQL'
    query($projectFullPath: ID!, $issueIids: [String!]) {
      project(fullPath: $projectFullPath) {
        issues(iids: $issueIids) {
          nodes { ...GitlabClient::CoreIssueFragment }
        }
      }
    }
  GRAPHQL

  ReviewerQuery = Client.parse <<-'GRAPHQL'
    query($reviewer: String!, $activeReviewsAfter: Time) {
      user(username: $reviewer) {
        ...GitlabClient::ExtendedUserFragment
        bot
        activeReviews: reviewRequestedMergeRequests(state: opened, approved: false, updatedAfter: $activeReviewsAfter) {
          # count # approved: false filter is behind the `mr_approved_filter` ops FF, so we need to request the nodes for now
          nodes { approved }
        }
      }
    }
  GRAPHQL

  OpenMergeRequestsQuery = Client.parse <<-'GRAPHQL'
    query($username: String!, $updatedAfter: Time) {
      user(username: $username) {
        openMergeRequests: authoredMergeRequests(state: opened, sort: UPDATED_DESC, updatedAfter: $updatedAfter) {
          nodes {
            ...GitlabClient::CoreMergeRequestFragment
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
                username
                mergeRequestInteraction {
                  approved
                  reviewState
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
  GRAPHQL

  MergedMergeRequestsQuery = Client.parse <<-'GRAPHQL'
    query($username: String!, $mergedAfter: Time!) {
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
        mergedMergeRequests: authoredMergeRequests(state: merged, mergedAfter: $mergedAfter, sort: MERGED_AT_DESC) {
          nodes {
            iid
            ...GitlabClient::CoreMergeRequestFragment
            mergedAt
            mergeUser {
              ...GitlabClient::ExtendedUserFragment
            }
          }
        }
      }
    }
  GRAPHQL

  MonthlyMergeRequestsQuery = Client.parse <<-'GRAPHQL'
    query($username: String!, $mergedAfter: Time, $mergedBefore: Time) {
      user(username: $username) {
        monthlyMergedMergeRequests: authoredMergeRequests(
          state: merged,
          mergedAfter: $mergedAfter,
          mergedBefore: $mergedBefore
        ) { ...GitlabClient::MonthlyMergeRequestStatsFragment }
      }
    }
  GRAPHQL
  # rubocop:enable Style/RedundantHeredocDelimiterQuotes

  def make_full_url(path)
    return path if path.nil? || path.start_with?("http")

    "#{self.class.gitlab_instance_url}#{path}"
  end

  def fetch_user(username, format: :open_struct)
    return format_response(format) { execute_query(UserQuery, "user", username: username) } if username.present?

    format_response(format) { execute_query(CurrentUserQuery, "user") }
  end

  def fetch_reviewer(username, format: :open_struct)
    format_response(format) do
      execute_query(
        ReviewerQuery,
        "reviewer",
        reviewer: username,
        activeReviewsAfter: 1.week.ago
      )
    end
  end

  def fetch_open_merge_requests(username, format: :open_struct)
    format_response(format) do
      execute_query(
        OpenMergeRequestsQuery,
        "open_merge_requests",
        username: username,
        updatedAfter: 1.year.ago
      )
    end
  end

  def fetch_merged_merge_requests(username, format: :open_struct)
    format_response(format) do
      execute_query(
        MergedMergeRequestsQuery, "merged_merge_requests", username: username, mergedAfter: 1.week.ago
      )
    end
  end

  def fetch_monthly_merged_merge_requests(username, format: :open_struct)
    format_response(format) do
      Sync do |task|
        12.times.map do |offset|
          bom = Date.current.beginning_of_month - offset.months
          eom = 1.month.after(bom)

          task.async do
            execute_query(
              MonthlyMergeRequestsQuery, "monthly_merged_merge_requests",
              username: username,
              mergedAfter: bom.to_fs,
              mergedBefore: eom.to_fs
            )
          end
        end.map(&:wait)
      end
    end.tap do |aggregate|
      next unless format == :open_struct

      user = OpenStruct.new
      aggregate.response.each_with_index do |monthly_result, offset|
        user["monthlyMergedMergeRequests#{offset}"] = monthly_result.data.user.delete_field!("monthlyMergedMergeRequests")
      end

      aggregate.response = OpenStruct.new(data: OpenStruct.new(user: user))
    end
  end

  # Fetches a list of issues given 2 lists of MRs, represented by a hash of { project_full_path:, issue_iid: }
  def fetch_issues(merged_mr_issue_iids, open_mr_issue_iids, format: :open_struct)
    issue_iids = (open_mr_issue_iids + merged_mr_issue_iids).filter { |h| h[:issue_iid] }.uniq
    project_full_paths = issue_iids.pluck(:project_full_path).uniq

    format_response(format) do
      Sync do |task|
        project_full_paths.map do |project_full_path|
          task.async do
            execute_query(
              ProjectIssuesQuery, "project_issues",
              projectFullPath: project_full_path,
              issueIids: issue_iids.filter { |h| h[:project_full_path] == project_full_path }.pluck(:issue_iid)
            )
          end
        end.map(&:wait)
      end
    end.tap do |aggregate|
      next unless format == :open_struct

      aggregate.response = OpenStruct.new(
        data: aggregate.response.flat_map { |project_response| project_response.data.project&.issues&.nodes }
      )
    end
  end

  private

  def execute_query(query, name, **args)
    Rails.logger.debug { %(Executing "#{name}" GraphQL query (args: #{args})...) }

    metric_source "graphql_metrics"
    metric_attributes(name: name, **args.slice(:username))

    handler = proc do |exception, _attempt_number, _total_delay|
      increment_counter "graphql.query.error_count", {exception: exception.class.name}
    end

    result = nil
    with_retries(max_tries: 2, handler: handler, rescue: [Graphlient::Errors::TimeoutError, Faraday::SSLError]) do
      increment_counter "graphql.query.count"

      histogram "graphql.query.duration" do
        result = Client.query(query, **args)
      end
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
end
