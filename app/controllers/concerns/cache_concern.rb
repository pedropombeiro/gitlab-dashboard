# frozen_string_literal: true

module CacheConcern
  extend ActiveSupport::Concern

  REDIS_NAMESPACE = "gitlab_dashboard"

  USER_CACHE_VALIDITY = 1.day
  MR_CACHE_VALIDITY = 5.minutes

  def user_cache_key(username)
    "#{REDIS_NAMESPACE}/user_info/v2/#{user_hash(username)}"
  end

  def open_issues_cache_key(issue_iids)
    "#{REDIS_NAMESPACE}/issues/v2/open/#{issue_iids.join("-")}"
  end

  def authored_mr_lists_cache_key(user)
    "#{REDIS_NAMESPACE}/merge_requests/v2/authored_list/#{user_hash(user)}"
  end

  def last_authored_mr_lists_cache_key(user)
    "#{REDIS_NAMESPACE}/merge_requests/v2/last_authored_list/#{user_hash(user)}"
  end

  private

  def user_hash(username)
    Digest::SHA256.hexdigest(username || ENV["GITLAB_TOKEN"] || "Anonymous")[0..15]
  end
end
