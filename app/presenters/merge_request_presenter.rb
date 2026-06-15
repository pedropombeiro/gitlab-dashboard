# frozen_string_literal: true

class MergeRequestPresenter
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::TextHelper
  include ActionView::Helpers::UrlHelper
  include ActionView::Context
  include HumanizeHelper

  attr_reader :merge_request, :view_context

  def initialize(merge_request, view_context = nil)
    @merge_request = merge_request
    @view_context = view_context
  end

  def milestone_class
    return unless merge_request.milestone

    milestone_mismatch = merge_request.milestone.title != (merge_request.issue&.milestone&.title || merge_request.milestone.title)
    milestone_mismatch ||= merge_request.project.version && !merge_request.project.version.start_with?(merge_request.milestone.title)
    milestone_mismatch ? "text-warning" : nil
  end

  def milestone_mismatch_tooltip
    return unless merge_request.milestone

    if merge_request.milestone.title != (merge_request.issue&.milestone&.title || merge_request.milestone.title)
      return "Merge request is assigned to #{merge_request.milestone.title} but issue is assigned to #{merge_request.issue&.milestone&.title}"
    end

    if merge_request.project.version && !merge_request.project.version.start_with?(merge_request.milestone.title)
      "Merge request is assigned to #{merge_request.milestone.title} but the active milestone for the project is #{merge_request.project.version}"
    end
  end

  def approvals_tooltip
    header = tag.strong("#{pluralize(merge_request.approvalsLeft, "approval")} missing")

    code_owner_rules = blocking_approval_rules
      .select { |rule| rule.type == "CODE_OWNER" && rule.name.present? }

    return header if code_owner_rules.empty?

    rule_items = code_owner_rules.map { |rule| tag.li(code_owner_rule_label(rule)) }.join
    [
      header,
      tag.div("Code owner approval needed:", class: "mt-1"),
      tag.ul(rule_items.html_safe, class: "text-start ps-3 mb-0")
    ].join.html_safe
  end

  private

  def code_owner_rule_label(rule)
    label = tag.code(rule.name)

    details = []
    required = rule.approvalsRequired.to_i
    details << "needs #{required}" if required > 1
    pool_size = rule.eligibleApprovers&.size.to_i
    details << pluralize(pool_size, "eligible approver") if pool_size.positive?

    label += tag.small(" (#{details.join(", ")})", class: "opacity-75") if details.any?
    label
  end

  def blocking_approval_rules
    rules = merge_request.approvalState&.rules
    return [] if rules.blank?

    rules.reject(&:approved)
  end
end
