# frozen_string_literal: true

require "async"
require "ostruct"

class GitlabClient
  ACTIVE_REVIEWS_AGE_LIMIT = 1.week
  OPEN_MERGE_REQUESTS_MIN_ACTIVITY = 1.year

  private_class_method def self.gitlab_token
    @gitlab_token = ENV.fetch("GITLAB_TOKEN", Rails.application.credentials.gitlab_token)
  end

  private_class_method def self.authorization
    "Bearer #{gitlab_token}"
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

  def make_full_url(path)
    return path if path.nil? || path.start_with?("http")

    "#{self.class.gitlab_instance_url}#{path}"
  end

  def fetch_user(username, format: :open_struct)
    return format_response(format) { execute_query(UserQuery, username: username) } if username.present?

    format_response(format) { execute_query(CurrentUserQuery) }
  end

  def fetch_reviewer(username, format: :open_struct)
    format_response(format) do
      execute_query(ReviewerQuery, reviewer: username, activeReviewsAfter: ACTIVE_REVIEWS_AGE_LIMIT.ago)
    end.tap do |response|
      next if format == :yaml_fixture

      reviewer = response.response.data.user
      compute_active_reviews(reviewer)
    end
  end

  def fetch_open_merge_requests(author, format: :open_struct)
    format_response(format) do
      execute_query(OpenMergeRequestsQuery, author: author, updatedAfter: OPEN_MERGE_REQUESTS_MIN_ACTIVITY.ago)
    end
  end

  def fetch_merged_merge_requests(author, format: :open_struct)
    format_response(format) do
      execute_query(MergedMergeRequestsQuery, author: author, mergedAfter: 1.week.ago)
    end
  end

  def fetch_monthly_merged_merge_requests(author, format: :open_struct)
    format_response(format) do
      Sync do |task|
        12.times.map do |offset|
          bom = offset.months.ago.beginning_of_month.to_date
          eom = bom.next_month

          task.async do
            execute_query(
              MonthlyMergeRequestsQuery,
              author: author,
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

  # Fetches a list of issues given a lists of MRs, represented by a hash of { project_full_path:, issue_iid: }
  def fetch_issues(issue_iids, format: :open_struct)
    issue_iids = issue_iids.filter { |h| h[:issue_iid] }.uniq
    project_full_paths = issue_iids.pluck(:project_full_path).uniq

    format_response(format) do
      Sync do |task|
        project_full_paths.map do |project_full_path|
          task.async do
            execute_query(
              ProjectIssuesQuery,
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

  def fetch_project_version(project_web_url)
    res = %w[master main].find do |branch|
      uri = project_version_file_uri(project_web_url, branch)
      res = Net::HTTP.get_response(uri)
      break res unless res.is_a?(Net::HTTPNotFound)
    end

    res.body.strip.delete_suffix("-pre") if res.is_a?(Net::HTTPSuccess)
  end

  def fetch_group_reviewers(group_path, format: :open_struct)
    format_response(format) do
      execute_query(
        GroupReviewersQuery,
        fullPath: group_path,
        activeReviewsAfter: 1.month.ago,
        activeAssignmentsAfter: 2.months.ago
      )
    end.tap do |response|
      group = response.response.data.group

      next if format == :yaml_fixture
      next if group.nil?

      group.groupMembers.nodes.flat_map(&:user).each do |reviewer|
        compute_active_reviews(reviewer)
      end
    end
  end

  GRAPHQL_RETRIABLE_ERRORS = [
    Faraday::SSLError,
    Graphlient::Errors::ConnectionFailedError,
    Graphlient::Errors::FaradayServerError,
    Graphlient::Errors::TimeoutError
  ]

  # rubocop:disable Style/RedundantHeredocDelimiterQuotes -- we want to ensure we don't use interpolation
  CoreUserFragment = Client.parse <<-'GRAPHQL'
    fragment on User {
      username
      avatarUrl
      webUrl
    }
  GRAPHQL

  ExtendedUserFragment = Client.parse <<-GRAPHQL
    fragment on User {
      ...#{name}::CoreUserFragment
      lastActivityOn
      jobTitle
      location
      pronouns
      status {
        availability
        emoji
        message
      }
    }
  GRAPHQL

  CurrentUserFragment = Client.parse <<-GRAPHQL
    fragment on User {
      ...#{name}::CoreUserFragment
      jobTitle
      status {
        availability
        emoji
        message
      }
    }
  GRAPHQL

  ReviewerFragment = Client.parse <<-GRAPHQL
    fragment on User {
      ...#{name}::ExtendedUserFragment
      bot
      state
      activeReviews: reviewRequestedMergeRequests(state: opened, updatedAfter: $activeReviewsAfter) {
        nodes {
          approvedBy {
            nodes {
              username
            }
          }
        }
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

  CoreMergeRequestFragment = Client.parse <<-GRAPHQL
    fragment on MergeRequest {
      iid
      webUrl
      titleHtml
      project {
        fullPath
        webUrl
        avatarUrl
      }
      milestone {
        title
      }
      reference
      sourceBranch
      targetBranch
      createdAt
      updatedAt
      assignees {
        nodes { ...#{name}::CoreUserFragment }
      }
      labels {
        nodes { ...#{name}::CoreLabelFragment }
      }
    }
  GRAPHQL

  UserQuery = Client.parse <<-GRAPHQL
    query($username: String!) {
      user(username: $username) {
        ...#{name}::CurrentUserFragment
      }
    }
  GRAPHQL

  CurrentUserQuery = Client.parse <<-GRAPHQL
    query {
      user: currentUser {
        ...#{name}::CurrentUserFragment
      }
    }
  GRAPHQL

  ProjectIssuesQuery = Client.parse <<-GRAPHQL
    query($projectFullPath: ID!, $issueIids: [String!]) {
      project(fullPath: $projectFullPath) {
        issues(iids: $issueIids) {
          nodes {
            iid
            webUrl
            titleHtml
            state
            milestone {
              title
            }
            labels {
              nodes { ...#{name}::CoreLabelFragment }
            }
          }
        }
      }
    }
  GRAPHQL

  ReviewerQuery = Client.parse <<-GRAPHQL
    query($reviewer: String!, $activeReviewsAfter: Time) {
      user(username: $reviewer) {
        ...#{name}::ReviewerFragment
      }
    }
  GRAPHQL

  OpenMergeRequestsQuery = Client.parse <<-GRAPHQL
    query($author: String!, $updatedAfter: Time) {
      user(username: $author) {
        openMergeRequests: authoredMergeRequests(state: opened, sort: UPDATED_DESC, updatedAfter: $updatedAfter) {
          nodes {
            ...#{name}::CoreMergeRequestFragment
            approved
            approvalsRequired
            approvalsLeft
            autoMergeEnabled
            detailedMergeStatus
            squashOnMerge
            conflicts
            commitCount
            blockingMergeRequests {
              visibleMergeRequests {
                iid
                reference
                state
                sourceBranch
                webUrl
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

  MergedMergeRequestsQuery = Client.parse <<-GRAPHQL
    query($author: String!, $mergedAfter: Time!) {
      user(username: $author) {
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
            ...#{name}::CoreMergeRequestFragment
            mergedAt
            mergeUser {
              ...#{name}::ExtendedUserFragment
            }
          }
        }
      }
    }
  GRAPHQL

  MonthlyMergeRequestsQuery = Client.parse <<-'GRAPHQL'
    query($author: String!, $mergedAfter: Time, $mergedBefore: Time) {
      user(username: $author) {
        monthlyMergedMergeRequests: authoredMergeRequests(
          state: merged,
          mergedAfter: $mergedAfter,
          mergedBefore: $mergedBefore
        ) {
          count
          totalTimeToMerge
        }
      }
    }
  GRAPHQL

  GroupReviewersQuery = Client.parse <<-GRAPHQL
    query($fullPath: ID!, $activeReviewsAfter: Time, $activeAssignmentsAfter: Time) {
      group(fullPath: $fullPath) {
        groupMembers(relations: DIRECT) {
          nodes {
            user {
              ...#{name}::ReviewerFragment
              assignedMergeRequests(state: opened, updatedAfter: $activeAssignmentsAfter) {
                count
              }
            }
          }
        }
      }
    }
  GRAPHQL
  # rubocop:enable Style/RedundantHeredocDelimiterQuotes

  private

  def execute_query(query, **args)
    Rails.logger.debug { %(Executing #{query.operation_name} GraphQL query (args: #{args})...) }

    with_retries(max_tries: 2, rescue: GRAPHQL_RETRIABLE_ERRORS) do
      Client.query(query, **args)
    end
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

  def project_version_file_uri(project_web_url, branch)
    URI("#{project_web_url}/-/raw/#{branch}/VERSION")
  end

  def compute_active_reviews(reviewer)
    reviewer.activeReviews[:count] =
      reviewer.activeReviews.delete_field!(:nodes)
        .map { |review| review.approvedBy.nodes.flat_map(&:username) }
        .count { |approved_by| approved_by.exclude?(reviewer.username) }
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
