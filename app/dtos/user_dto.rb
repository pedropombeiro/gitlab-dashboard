# frozen_string_literal: true

class UserDto
  extend ActiveModel::Naming

  include ActiveModel::Conversion
  include MrStatusOrnamentsConcern
  include ReviewerOrnamentsConcern
  include MergeRequestsParsingHelper

  PIPELINE_AGE_LIMIT = 8.hours

  attr_reader :errors, :updated_at, :next_update_at, :request_duration
  attr_reader :open_merge_requests, :merged_merge_requests, :type
  attr_reader :merged_merge_requests_count, :merged_merge_requests_tttm, :first_merged_merge_requests_timestamp

  def initialize(response, username, type, issues_by_iid)
    @has_content = response.present?
    @username = username

    unless response
      @open_merge_requests = MergeRequestCollectionDto.new([])
      @merged_merge_requests = MergeRequestCollectionDto.new([])
      return
    end

    @type = type
    @errors = response.errors
    @request_duration = response.request_duration
    @updated_at = response.updated_at
    return if @errors

    @next_update_at = response.next_update_at

    case @type
    when :open
      open_mrs = response.user.openMergeRequests.nodes

      warmup_timezone_cache(open_mrs)

      @open_merge_requests = MergeRequestCollectionDto.new(
        open_mrs.map { |mr| convert_open_merge_request(mr, open_mrs, issues_by_iid) }
      )
    when :merged
      merged_mrs = response.user.mergedMergeRequests.nodes

      @merged_merge_requests_count = response.user.allMergedMergeRequests.count
      @merged_merge_requests_tttm = response.user.allMergedMergeRequests.totalTimeToMerge
      @first_merged_merge_requests_timestamp =
        parse_graphql_time(response.user.firstCreatedMergedMergeRequests.nodes.first&.createdAt)
      @merged_merge_requests = MergeRequestCollectionDto.new(
        merged_mrs.map { |mr| convert_merged_merge_request(mr, merged_mrs, issues_by_iid) }
      )
    end
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
    locations = mrs.flat_map { |mr| mr.reviewers.nodes.map(&:location) }.compact_blank.uniq

    location_lookup_service.fetch_timezones(locations)
  end

  def convert_mr_pipeline(pipeline)
    return unless pipeline

    pipeline.startedAt = parse_graphql_time(pipeline.startedAt)
    pipeline.finishedAt = parse_graphql_time(pipeline.finishedAt)
  end

  def convert_core_merge_request(merge_request, merge_requests, issues_by_iid, contextual_labels)
    merge_request.tap do |mr|
      mr.issue = issue_from_mr(mr, issues_by_iid)
      mr.createdAt = parse_graphql_time(mr.createdAt)
      mr.updatedAt = parse_graphql_time(mr.updatedAt)

      mr.contextualLabels =
        mr.labels.nodes.filter { |label| contextual_labels.any? { |prefix| label.title.start_with?(prefix.to_s) } }
      mr.contextualLabels.each { |label| label.webTitle = label.title }

      if mr.approved
        # GitLab returns 'approved == true' if no review has actually happened, which is a bit misleading
        mr.approved = false if mr.reviewers.nodes.any? { |reviewer| !reviewer.mergeRequestInteraction.approved }
      end

      if mr.issue
        mr.issue.contextualLabels = mr.issue.labels.nodes.filter do |label|
          issue_contextual_labels.any? { |prefix| label.title.start_with?(prefix) }
        end

        mr.issue.contextualLabels.each do |label|
          label.bootstrapClass = [] # Use label's predefined colors
          label.webTitle = label.title.delete_prefix(workflow_label_ns)
        end
      end

      mr.upstreamMergeRequest =
        merge_requests.find { |target_mr| mr.targetBranch == target_mr.sourceBranch } ||
        mr.blockingMergeRequests&.visibleMergeRequests&.find { |target_mr| mr.targetBranch == target_mr.sourceBranch }
    end
  end

  def convert_open_merge_request(merge_request, open_merge_requests, issues_by_iid)
    convert_core_merge_request(merge_request, open_merge_requests, issues_by_iid, open_mrs_contextual_labels).tap do |mr|
      mr.state = :open
      mr.bootstrapClass = {
        pipeline: pipeline_class(mr.headPipeline),
        mergeStatus: open_merge_request_status_class(mr)
      }

      convert_mr_pipeline(mr.headPipeline)

      if mr.headPipeline
        mr.headPipeline[:outdated?] =
          mr.headPipeline.startedAt &&
          mr.headPipeline.finishedAt&.before?(PIPELINE_AGE_LIMIT.ago) &&
          "pipeline::tier-3".in?(mr.contextualLabels.map(&:title))
      end

      mr.mergeStatusLabel = open_merge_request_status_label(mr)
      mr.blocked =
        mr.detailedMergeStatus == "BLOCKED_STATUS" ||
        mr.blockingMergeRequests.visibleMergeRequests.any? { |blocker_mr| blocker_mr.state == "opened" }

      mr.labels.nodes.each { |label| label.bootstrapClass = [] } # Use label's predefined colors

      mr.reviewers.nodes.delete_if(&:bot)
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

  def convert_merged_merge_request(merge_request, merged_merge_requests, issues_by_iid)
    convert_core_merge_request(
      merge_request,
      merged_merge_requests,
      issues_by_iid,
      merged_mrs_contextual_labels
    ).tap do |mr|
      mr.state = :merged
      mr.mergedAt = parse_graphql_time(mr.mergedAt)
      mr.mergeUser.lastActivityOn = parse_graphql_time(mr.mergeUser.lastActivityOn)

      mr.labels.nodes.each do |label|
        label.bootstrapClass = workflow_label_class(label.title)
        label.webTitle = label.title.delete_prefix(workflow_label_ns)
      end
    end
  end

  def user_activity_icon_class(user)
    return if user.lastActivityOn.nil?

    %w[fa-solid fa-moon] if user.lastActivityOn.before?(Time.current.beginning_of_day)
  end

  def location_lookup_service
    @location_lookup_service ||= LocationLookupService.new
  end

  def merged_mrs_contextual_labels
    @merged_mrs_contextual_labels ||= deployment_labels + workflow_labels
  end
end
