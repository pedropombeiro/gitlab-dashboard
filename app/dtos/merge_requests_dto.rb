# frozen_string_literal: true

class MergeRequestsDto
  include MrStatusOrnamentsConcern
  include ReviewerOrnamentsConcern
  include MergeRequestsParsingHelper

  DEPLOYMENT_LABELS = ["Pick into auto-deploy"].freeze
  WORKFLOW_LABELS = WORKFLOW_LABELS_BS_CLASS.keys.freeze
  OPEN_MRS_CONTEXTUAL_LABELS = ["pipeline::"].freeze
  MERGED_MRS_CONTEXTUAL_LABELS = (DEPLOYMENT_LABELS + WORKFLOW_LABELS).freeze
  ISSUE_CONTEXTUAL_LABELS = ["workflow::"].freeze

  attr_reader :errors, :updated_at, :request_duration, :next_update
  attr_reader :open_merge_requests, :merged_merge_requests

  def initialize(response, open_issues_by_iid, cache_validity)
    @open_merge_requests = []
    @merged_merge_requests = []
    @next_update = 1.minute.after(Time.now)
    @has_content = response.present?

    return unless response

    @errors = response.errors
    @request_duration = response.request_duration
    @updated_at = response.updated_at
    return if @errors

    @next_update = cache_validity&.after(response.updated_at)

    open_mrs = response.user.openMergeRequests.nodes
    merged_mrs = response.user.mergedMergeRequests.nodes
    @open_merge_requests = open_mrs.map { |mr| convert_open_merge_request(mr, open_mrs, open_issues_by_iid) }
    @merged_merge_requests = filter_merged_merge_requests(merged_mrs, open_issues_by_iid).map do |mr|
      convert_merged_merge_request(mr, merged_mrs, open_issues_by_iid)
    end
  end

  def has_content?
    @has_content
  end

  private

  def parse_graphql_time(timestamp)
    Time.parse(timestamp) if timestamp
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
        contextual_labels.any? { |prefix| label.title.start_with?(prefix) }
      end

      if mr.issue
        mr.issue.contextualLabels = mr.issue.labels.nodes.filter do |label|
          ISSUE_CONTEXTUAL_LABELS.any? { |prefix| label.title.start_with?(prefix) }
          label.bootstrapClass = [] # Use label's predefined colors
          label.title.delete_prefix!(WORKFLOW_LABEL_NS)
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

      mr.mergeStatusLabel = open_merge_request_status_label(mr)
      mr.labels.nodes.each { |label| label.bootstrapClass = [] } # Use label's predefined colors
      mr.reviewers.nodes.each do |reviewer|
        reviewer.lastActivityOn = parse_graphql_time(reviewer.lastActivityOn)
        reviewer.review = reviewer.mergeRequestInteraction.reviewState
        reviewer.bootstrapClass = {
          text: review_text_class(reviewer),
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
        label.title.delete_prefix!(WORKFLOW_LABEL_NS)
      end
    end
  end

  def user_activity_icon_class(user)
    %w[fa-solid fa-moon] if user.lastActivityOn < 1.day.ago
  end

  def merge_request_issue_iids(merge_requests)
    merge_requests.to_h { |mr| [mr.iid, issue_iid_from_mr(mr)] }
  end

  def filter_merged_merge_requests(merge_requests, open_issues_by_iid)
    return unless open_issues_by_iid

    open_mr_issue_iids = open_issues_by_iid.keys
    merged_request_issue_iids = merge_request_issue_iids(merge_requests)

    merge_requests.filter do |mr|
      open_mr_issue_iids.include?(merged_request_issue_iids[mr.iid]) ||
        mr.mergedAt >= 2.days.ago
    end
  end
end
