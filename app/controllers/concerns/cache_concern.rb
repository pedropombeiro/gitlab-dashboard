# frozen_string_literal: true

module CacheConcern
  extend ActiveSupport::Concern

  REDIS_NAMESPACE = "gitlab_dashboard"

  USER_CACHE_VALIDITY = 1.day
  MR_CACHE_VALIDITY = 5.minutes
  MONTHLY_GRAPH_CACHE_VALIDITY = 3.hours

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
      "#{REDIS_NAMESPACE}/issues/#{project_issues_version}/open/#{calculate_hash(*issues.map { |issue| issue.values.join("/") })}"
    end

    def authored_mr_lists_cache_key(user)
      "#{REDIS_NAMESPACE}/merge_requests/#{merge_requests_version}/authored_list/#{user_hash(user)}"
    end

    def monthly_merged_mr_lists_cache_key(user)
      "#{REDIS_NAMESPACE}/merge_requests/#{monthly_merge_request_stats_version}/monthly_merged/#{user_hash(user)}"
    end

    def last_authored_mr_lists_cache_key(user)
      "#{REDIS_NAMESPACE}/merge_requests/#{merge_requests_version}/last_authored_list/#{user_hash(user)}"
    end

    private

    def calculate_hash(*args)
      value =
        if args.many?
          args.map { |arg| Digest::SHA256.hexdigest(arg) }.join
        else
          args.first || ""
        end

      Digest::SHA256.hexdigest(value)[0..15]
    end

    def user_hash(username)
      calculate_hash(username&.downcase || Rails.application.credentials.gitlab_token || "Anonymous")
    end

    def user_info_version
      @user_info_version ||= calculate_hash(GitlabClient::USER_QUERY, GitlabClient::CURRENT_USER_QUERY)
    end

    def project_issues_version
      @project_issues_version ||= calculate_hash(GitlabClient::PROJECT_ISSUES_QUERY)
    end

    def merge_requests_version
      @merge_requests_version ||= calculate_hash(
        GitlabClient::OPEN_MERGE_REQUESTS_GRAPHQL_QUERY,
        GitlabClient::MERGED_MERGE_REQUESTS_GRAPHQL_QUERY
      )
    end

    def monthly_merge_request_stats_version
      @monthly_merge_request_stats_version ||= calculate_hash(GitlabClient::MONTHLY_MERGE_REQUEST_STATS_QUERY)
    end
  end
end
