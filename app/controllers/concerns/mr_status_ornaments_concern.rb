# frozen_string_literal: true

module MrStatusOrnamentsConcern
  extend ActiveSupport::Concern

  MERGE_STATUS_BS_CLASS = {
    "BLOCKED_STATUS" => "warning",
    "REQUESTED_CHANGES" => "warning",
    "CI_STILL_RUNNING" => "primary",
    "MERGEABLE" => "success"
  }.freeze

  PIPELINE_BS_CLASS = {
    "SUCCESS" => "success",
    "FAILED" => "danger",
    "RUNNING" => "primary"
  }.freeze

  WORKFLOW_LABEL_NS = "workflow::"
  WORKFLOW_LABELS_BS_CLASS = {
    "#{WORKFLOW_LABEL_NS}staging-canary" => "info",
    "#{WORKFLOW_LABEL_NS}canary" => "info",
    "#{WORKFLOW_LABEL_NS}staging" => "info",
    "#{WORKFLOW_LABEL_NS}production" => "primary",
    "#{WORKFLOW_LABEL_NS}post-deploy-db-staging" => "success",
    "#{WORKFLOW_LABEL_NS}post-deploy-db-production" => "success"
  }.freeze

  def open_merge_request_status_class(mr)
    return "warning" if mr.conflicts
    return "secondary" if mr.detailedMergeStatus == "BLOCKED_STATUS"

    if mr.reviewers.nodes.map(&:mergeRequestInteraction).any? { |mri| mri.reviewState == "REVIEWED" && !mri.approved }
      return "warning"
    end

    MERGE_STATUS_BS_CLASS.fetch(mr.detailedMergeStatus, "secondary")
  end

  def pipeline_class(pipeline)
    PIPELINE_BS_CLASS.fetch(pipeline&.status, "secondary")
  end

  def workflow_label_class(label_title)
    return [] unless label_title.start_with?(WORKFLOW_LABEL_NS)

    [
      "bg-#{WORKFLOW_LABELS_BS_CLASS.fetch(label_title, "secondary")}",
      "text-light"
    ]
  end
end