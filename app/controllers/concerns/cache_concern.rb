# frozen_string_literal: true

module CacheConcern
  extend ActiveSupport::Concern

  REDIS_NAMESPACE = "gitlab_dashboard"

  USER_CACHE_VALIDITY = 1.day
  MR_CACHE_VALIDITY = 5.minutes

  class_methods do
    def user_cache_key(username)
      "#{REDIS_NAMESPACE}/user_info/v4/#{user_hash(username)}"
    end

    def open_issues_cache_key(issue_iids)
      "#{REDIS_NAMESPACE}/issues/v3/open/#{issue_iids.join("-")}"
    end

    def authored_mr_lists_cache_key(user)
      "#{REDIS_NAMESPACE}/merge_requests/v4/authored_list/#{user_hash(user)}"
    end

    def last_authored_mr_lists_cache_key(user)
      "#{REDIS_NAMESPACE}/merge_requests/v4/last_authored_list/#{user_hash(user)}"
    end

    private

    def user_hash(username)
      Digest::SHA256.hexdigest(username || Rails.application.credentials.gitlab_token || "Anonymous")[0..15]
    end
  end
end
