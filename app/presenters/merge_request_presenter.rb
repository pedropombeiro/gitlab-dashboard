# frozen_string_literal: true

class MergeRequestPresenter
  include ActionView::Helpers::TagHelper
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
end
