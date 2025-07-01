# frozen_string_literal: true

module MrStatusOrnamentsConcern
  extend ActiveSupport::Concern

  include HumanizeHelper

  def open_merge_request_status_class(mr)
    return "warning" if mr.conflicts
    return "warning" if returned_to_assignee?(mr)
    return "secondary" if waiting_for_others?(mr)

    config.dig(:status, :mappings).fetch(mr.detailedMergeStatus.to_sym, "secondary")
  end

  def open_merge_request_status_label(mr)
    return "Returned to you" if returned_to_assignee?(mr)
    return "Waiting for others" if waiting_for_others?(mr)

    humanized_enum(mr.detailedMergeStatus.delete_suffix("_STATUS"))
  end

  def pipeline_class(pipeline)
    config.dig(:pipeline, :mappings).fetch(pipeline&.status&.to_sym, "secondary")
  end

  def workflow_label_class(label_title)
    class_name = config.dig(:labels, :workflow, :mappings, label_title&.to_sym)&.fetch(:class, "secondary")
    return [] unless class_name

    %W[
      bg-#{class_name}
      text-light
    ]
  end

  def issue_contextual_labels
    @@issue_contextual_labels ||= config.dig(:labels, :issue, :contextual)
  end

  def deployment_labels
    @@deployment_labels ||= config.dig(:labels, :deployment, :contextual)
  end

  def open_mrs_contextual_labels
    @@open_mrs_contextual_labels ||= config.dig(:labels, :open_merge_requests, :contextual)
  end

  def workflow_labels
    @@workflow_labels ||= config.dig(:labels, :workflow, :mappings).keys
  end

  def convert_label(label)
    config.dig(:labels, :workflow, :mappings, label.to_sym, :title)
  end

  private

  def waiting_for_others?(mr)
    mr.detailedMergeStatus.in?(%w[UNREVIEWED UNAPPROVED REVIEW_STARTED])
  end

  def returned_to_assignee?(mr)
    mr_interactions = mr.reviewers.nodes.map(&:mergeRequestInteraction)

    # Signal that a reviewer forgot to pass on the review to the follow-up reviewer
    return true if mr.approvalsLeft&.positive? && mr_interactions.all?(&:approved)

    mr_interactions.map(&:reviewState).include?(%w[REVIEWED REQUESTED_CHANGES])
  end

  def config
    @@merge_requests_config ||= Rails.application.config.merge_requests
  end
end
