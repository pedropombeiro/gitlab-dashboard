# frozen_string_literal: true

class UserDto
  extend ActiveModel::Naming

  include ActiveModel::Conversion
  include MrStatusOrnamentsConcern
  include ReviewerOrnamentsConcern
  include MergeRequestsParsingHelper

  DEPLOYMENT_LABELS = ["Pick into auto-deploy"].freeze
  WORKFLOW_LABELS = WORKFLOW_LABELS_BS_CLASS.keys.freeze
  OPEN_MRS_CONTEXTUAL_LABELS = ["pipeline::"].freeze
  MERGED_MRS_CONTEXTUAL_LABELS = (DEPLOYMENT_LABELS + WORKFLOW_LABELS).freeze
  ISSUE_CONTEXTUAL_LABELS = ["workflow::"].freeze

  attr_reader :errors, :updated_at, :next_update_at, :request_duration
  attr_reader :open_merge_requests, :merged_merge_requests
  attr_reader :merged_merge_requests_count, :merged_merge_requests_tttm, :first_merged_merge_requests_timestamp

  def initialize(response, username, open_issues_by_iid)
    @has_content = response.present?
    @username = username

    unless response
      @open_merge_requests = MergeRequestCollectionDto.new([])
      @merged_merge_requests = MergeRequestCollectionDto.new([])
      return
    end

    @errors = response.errors
    @request_duration = response.request_duration
    @updated_at = response.updated_at
    return if @errors

    @next_update_at = response.next_update_at

    open_mrs = response.user.openMergeRequests.nodes
    merged_mrs = response.user.mergedMergeRequests.nodes

    warmup_timezone_cache(open_mrs)

    @open_merge_requests = MergeRequestCollectionDto.new(
      open_mrs.map { |mr| convert_open_merge_request(mr, open_mrs, open_issues_by_iid) }
    )
    @merged_merge_requests_count = response.user.allMergedMergeRequests.count
    @merged_merge_requests_tttm = response.user.allMergedMergeRequests.totalTimeToMerge
    @first_merged_merge_requests_timestamp =
      parse_graphql_time(response.user.firstCreatedMergedMergeRequests.nodes.first&.createdAt)
    @merged_merge_requests = MergeRequestCollectionDto.new(
      filter_merged_merge_requests(merged_mrs).map do |mr|
        convert_merged_merge_request(mr, merged_mrs, open_issues_by_iid)
      end
    )
  end

  def has_content?
    @has_content
  end

  # https://apidock.com/rails/ActiveModel/Conversion
  def id
    @username
  end

  def persisted?
    true
  end

  private

  def parse_graphql_time(timestamp)
    Time.zone.parse(timestamp) if timestamp
  end

  def warmup_timezone_cache(mrs)
    locations = mrs.filter_map { |mr| mr.reviewers.nodes.map(&:location).map(&:presence) }.flatten.compact.uniq

    Services::TimezoneService.new.fetch_from_locations(locations)
  end

  def convert_mr_pipeline(pipeline)
    return unless pipeline

    pipeline.startedAt = parse_graphql_time(pipeline.startedAt)
    pipeline.finishedAt = parse_graphql_time(pipeline.finishedAt)
    if pipeline.status == "RUNNING"
      pipeline.status += " (#{pipeline.finishedJobs.count.to_i * 100 / pipeline.jobs.count.to_i}%)"
    end
  end

  def convert_core_merge_request(merge_request, merge_requests, open_issues_by_iid, contextual_labels)
    merge_request.tap do |mr|
      mr.issue = issue_from_mr(mr, open_issues_by_iid)
      mr.createdAt = parse_graphql_time(mr.createdAt)
      mr.updatedAt = parse_graphql_time(mr.updatedAt)

      mr.contextualLabels = mr.labels.nodes.filter do |label|
        label.webTitle = label.title
        contextual_labels.any? { |prefix| label.title.start_with?(prefix) }
      end

      if mr.issue
        mr.issue.contextualLabels = mr.issue.labels.nodes.filter do |label|
          next false unless ISSUE_CONTEXTUAL_LABELS.any? { |prefix| label.title.start_with?(prefix) }

          label.bootstrapClass = [] # Use label's predefined colors
          label.webTitle = label.title.delete_prefix(WORKFLOW_LABEL_NS)

          true
        end
      end

      mr.upstreamMergeRequest = merge_requests.select do |target_mr|
        mr.targetBranch == target_mr.sourceBranch
      end&.first
    end
  end

  def convert_open_merge_request(merge_request, open_merge_requests, open_issues_by_iid)
    convert_core_merge_request(merge_request, open_merge_requests, open_issues_by_iid, OPEN_MRS_CONTEXTUAL_LABELS).tap do |mr|
      mr.bootstrapClass = {
        pipeline: pipeline_class(mr.headPipeline),
        mergeStatus: open_merge_request_status_class(mr)
      }

      convert_mr_pipeline(mr.headPipeline)

      if mr.headPipeline
        mr.headPipeline[:outdated?] =
          mr.headPipeline.startedAt &&
          mr.headPipeline.finishedAt &&
          mr.headPipeline.finishedAt < 8.hours.ago &&
          mr.contextualLabels.any? { |label| label.title == "pipeline::tier-3" }
      end

      mr.mergeStatusLabel = open_merge_request_status_label(mr)
      mr.labels.nodes.each { |label| label.bootstrapClass = [] } # Use label's predefined colors
      mr.reviewers.nodes.each do |reviewer|
        reviewer.lastActivityOn = parse_graphql_time(reviewer.lastActivityOn)
        reviewer.review = reviewer.mergeRequestInteraction.reviewState
        reviewer.bootstrapClass = {
          badge: review_badge_class(reviewer),
          icon: review_icon_class(reviewer),
          activity_icon: user_activity_icon_class(reviewer)
        }.compact
      end
    end
  end

  def convert_merged_merge_request(merge_request, merged_merge_requests, open_issues_by_iid)
    convert_core_merge_request(merge_request, merged_merge_requests, open_issues_by_iid, MERGED_MRS_CONTEXTUAL_LABELS).tap do |mr|
      mr.mergedAt = parse_graphql_time(mr.mergedAt)
      mr.mergeUser.lastActivityOn = parse_graphql_time(mr.mergeUser.lastActivityOn)

      mr.labels.nodes.each do |label|
        label.bootstrapClass = workflow_label_class(label.title)
        label.webTitle = label.title.delete_prefix(WORKFLOW_LABEL_NS)
      end
    end
  end

  def user_activity_icon_class(user)
    %w[fa-solid fa-moon] if user.lastActivityOn < 1.day.ago
  end

  def filter_merged_merge_requests(merge_requests)
    merge_requests.filter { |mr| mr.mergedAt >= 1.week.ago }
  end
end
