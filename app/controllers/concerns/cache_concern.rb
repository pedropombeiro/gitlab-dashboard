# frozen_string_literal: true

module CacheConcern
  extend ActiveSupport::Concern

  REDIS_NAMESPACE = "gitlab_dashboard"

  USER_CACHE_VALIDITY = 1.day
  MR_CACHE_VALIDITY = 5.minutes
  REVIEWER_VALIDITY = 30.minutes
  MONTHLY_GRAPH_CACHE_VALIDITY = 3.hours
  GROUP_REVIEWERS_CACHE_VALIDITY = 1.hour
  PROJECT_VERSION_VALIDITY = 6.hours

  LOCATION_VERSION = "v2"

  class_methods do
    def user_cache_key(username)
      "#{REDIS_NAMESPACE}/user_info/#{user_info_version}/#{user_hash(username)}"
    end

    def location_info_cache_key(location)
      "#{REDIS_NAMESPACE}/location/#{LOCATION_VERSION}/#{calculate_hash(location)}"
    end

    def location_timezone_name_cache_key(location)
      "#{REDIS_NAMESPACE}/location/#{LOCATION_VERSION}/#{calculate_hash(location)}/timezone_name"
    end

    def project_issues_cache_key(issues)
      issue_iids = issues.map { |issue| issue.values.join("/") }.sort
      "#{REDIS_NAMESPACE}/issues/#{project_issues_version}/#{calculate_hash(*issue_iids)}"
    end

    def reviewer_cache_key(username)
      "#{REDIS_NAMESPACE}/reviewer_info/#{reviewer_info_version}/#{user_hash(username)}"
    end

    def project_version_cache_key(project_full_path)
      "#{REDIS_NAMESPACE}/project_version/#{calculate_hash(project_full_path)}"
    end

    def authored_mr_lists_cache_key(user, type)
      "#{REDIS_NAMESPACE}/merge_requests/#{merge_requests_version}/authored_#{type}_list/#{user_hash(user)}"
    end

    def monthly_merged_mr_lists_cache_key(user)
      "#{REDIS_NAMESPACE}/merge_requests/#{monthly_merge_request_stats_version}/monthly_merged/#{user_hash(user)}"
    end

    def last_authored_mr_lists_cache_key(user, type)
      "#{REDIS_NAMESPACE}/merge_requests/#{merge_requests_version}/last_authored_#{type}_list/#{user_hash(user)}"
    end

    def group_reviewers_cache_key(group_full_path)
      "#{REDIS_NAMESPACE}/group/#{calculate_hash(group_full_path)}/reviewers"
    end

    private

    def value_as_string(obj)
      case obj
      when GraphQL::Client::OperationDefinition
        obj.document.to_query_string
      else
        obj.to_s
      end
    end

    def calculate_hash(*args)
      value =
        if args.many?
          args.map { |arg| Digest::SHA256.hexdigest(value_as_string(arg)) }.join
        else
          value_as_string(args.first) || ""
        end

      Digest::SHA256.hexdigest(value)[0..15]
    end

    def user_hash(username)
      calculate_hash(username&.downcase || Rails.application.credentials.gitlab_token || "Anonymous")
    end

    def user_info_version
      @user_info_version ||= calculate_hash(GitlabClient::UserQuery, GitlabClient::CurrentUserQuery)
    end

    def reviewer_info_version
      @reviewer_info_version ||= calculate_hash(GitlabClient::ReviewerQuery)
    end

    def project_issues_version
      @project_issues_version ||= calculate_hash(GitlabClient::ProjectIssuesQuery)
    end

    def merge_requests_version
      @merge_requests_version ||= calculate_hash(
        GitlabClient::OpenMergeRequestsQuery,
        GitlabClient::ReviewerQuery,
        GitlabClient::MergedMergeRequestsQuery
      )
    end

    def monthly_merge_request_stats_version
      @monthly_merge_request_stats_version ||= calculate_hash(GitlabClient::MonthlyMergeRequestsQuery)
    end
  end
end
