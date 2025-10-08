# frozen_string_literal: true

class FetchMergeRequestsService
  include Honeybadger::InstrumentationHelper

  include CacheConcern
  include HumanizeHelper
  include MergeRequestsHelper
  include MergeRequestsParsingHelper
  include MergeRequestsPipelineHelper

  attr_reader :author
  delegate :make_full_url, to: :gitlab_client

  def initialize(author)
    @author = author
  end

  def execute(type)
    Rails.cache.fetch(
      self.class.authored_mr_lists_cache_key(author, type), expires_in: MergeRequestsCacheService.cache_validity
    ) do
      raw_response =
        case type
        when :open
          gitlab_client.fetch_open_merge_requests(author).tap do |response|
            merge_requests_from_response(response.response.data, type)
              .tap do |mrs|
                fill_reviewers_info(mrs)
                fill_project_milestone(mrs)
              end
          end
        when :merged
          gitlab_client.fetch_merged_merge_requests(author)
        end

      raw_response.response.data.tap do |response|
        response.updated_at = raw_response.updated_at
        response.request_duration = raw_response.request_duration
        response.next_update_at = MergeRequestsCacheService.cache_validity.after(raw_response.updated_at)
        response.next_scheduled_update_at =
          if type == :open
            mrs = merge_requests_from_response(response, type)
            if any_mwps_pipelines?(mrs)
              1.minute.from_now
            elsif any_running_pipelines?(mrs)
              5.minutes.from_now
            else
              30.minutes.from_now
            end
          else
            30.minutes.from_now
          end
      end
    end
  end

  def parse_dto(response, type)
    issues_by_iid = []
    if response && response.errors.nil?
      issues_by_iid = merge_requests_from_response(response, type).then { |mrs| issues_from_merge_requests(mrs) }
    end

    ::UserDto.new(response, author, type, issues_by_iid)
  end

  private

  def gitlab_client
    @gitlab_client ||= GitlabClient.new
  end

  def merge_requests_from_response(response, type)
    case type
    when :open
      response.user.openMergeRequests.nodes
    when :merged
      response.user.mergedMergeRequests.nodes
    end
  end

  def any_mwps_pipelines?(merge_requests)
    merge_requests
      .filter(&:autoMergeEnabled)
      .filter_map(&:headPipeline)
      .any? { |pipeline| pipeline.status == "PENDING" || (pipeline.startedAt.present? && pipeline.finishedAt.nil?) }
  end

  def any_running_pipelines?(merge_requests)
    merge_requests
      .filter_map(&:headPipeline)
      .any? { |pipeline| pipeline.status == "PENDING" || (pipeline.startedAt.present? && pipeline.finishedAt.nil?) }
  end

  def issues_from_merge_requests(merge_requests)
    issue_iids = merge_request_issue_iids(merge_requests).uniq

    Rails.cache.fetch(self.class.project_issues_cache_key(issue_iids), expires_in: MergeRequestsCacheService.cache_validity) do
      gitlab_client.fetch_issues(issue_iids)
    end.response&.data&.compact.to_h { |issue| [issue.iid, issue] }
  end

  def fill_project_milestone(open_merge_requests)
    project_full_paths = open_merge_requests.filter_map { |mr| mr.project.webUrl }.uniq

    project_versions = Sync do |task|
      project_full_paths.map do |project_full_path|
        task.async do
          Rails.cache.fetch(self.class.project_version_cache_key(project_full_path), expires_in: PROJECT_VERSION_VALIDITY) do
            gitlab_client.fetch_project_version(project_full_path).tap do |v|
              Rails.logger.info "#{project_full_path} = #{v}"
            end
          end
        end
      end.map(&:wait)
    end

    project_versions_hash = project_full_paths.zip(project_versions).to_h

    open_merge_requests.flat_map { |mr| mr.project }.each do |project|
      project[:version] = project_versions_hash[project.webUrl]
    end
  end

  def fill_reviewers_info(open_merge_requests)
    reviewer_usernames = open_merge_requests.flat_map { |mr| mr.reviewers.nodes.map(&:username) }.uniq

    reviewers_info = Sync do |task|
      reviewer_usernames.map do |reviewer_username|
        task.async do
          Rails.cache.fetch(self.class.reviewer_cache_key(reviewer_username), expires_in: REVIEWER_VALIDITY) do
            gitlab_client.fetch_reviewer(reviewer_username)
          end
        end
      end.map(&:wait)
    end

    reviewers_hash =
      reviewers_info
        .map { |response| response.response.data.user }
        .to_h { |reviewer| [reviewer.username, reviewer] }

    open_merge_requests.flat_map { |mr| mr.reviewers.nodes }.each do |reviewer|
      reviewer.table.reverse_merge!(reviewers_hash[reviewer.username].table)
    end
  end
end
