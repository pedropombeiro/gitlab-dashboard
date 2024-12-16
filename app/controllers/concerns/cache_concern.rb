# frozen_string_literal: true

module CacheConcern
  extend ActiveSupport::Concern

  REDIS_NAMESPACE = "gitlab_dashboard"

  USER_CACHE_VALIDITY = 1.day
  MR_CACHE_VALIDITY = 5.minutes
  MONTHLY_GRAPH_CACHE_VALIDITY = 3.hours

  MR_VERSION = 11

  class_methods do
    def user_cache_key(username)
      "#{REDIS_NAMESPACE}/user_info/v5/#{user_hash(username)}"
    end

    def location_info_cache_key(location)
      "#{REDIS_NAMESPACE}/location/v2/#{Digest::SHA256.hexdigest(location)}"
    end

    def location_timezone_name_cache_key(location)
      "#{REDIS_NAMESPACE}/location/v2/#{Digest::SHA256.hexdigest(location)}/timezone_name"
    end

    def open_issues_cache_key(issue_iids)
      "#{REDIS_NAMESPACE}/issues/v5/open/#{issue_iids.join("-")}"
    end

    def authored_mr_lists_cache_key(user)
      "#{REDIS_NAMESPACE}/merge_requests/v#{MR_VERSION}/authored_list/#{user_hash(user)}"
    end

    def monthly_merged_mr_lists_cache_key(user)
      "#{REDIS_NAMESPACE}/merge_requests/v2/monthly_merged/#{user_hash(user)}"
    end

    def last_authored_mr_lists_cache_key(user)
      "#{REDIS_NAMESPACE}/merge_requests/v#{MR_VERSION}/last_authored_list/#{user_hash(user)}"
    end

    private

    def user_hash(username)
      Digest::SHA256.hexdigest(username&.downcase || Rails.application.credentials.gitlab_token || "Anonymous")[0..15]
    end
  end
end
