# frozen_string_literal: true

require "ostruct"

module MergeRequestsParsingHelper
  MR_ISSUE_PATTERN = %r{\b(?<issue_id>\d+)[/-].+}i
  SECURITY_SUBGROUP = "/security"

  UNAVAILABLE_ISSUE_TITLE_HTML =
    "Issue details are unavailable - the GitLab token used by this dashboard cannot access this issue, " \
    "which may be confidential"

  def issue_from_mr(mr, issues_by_iid)
    iid = issue_iid_from_mr(mr)
    return unless iid

    issues_by_iid[iid] || unavailable_issue(mr, iid)
  end

  def issue_iid_from_mr(mr)
    work_item = linked_work_item(mr)&.workItem
    return work_item.iid if work_item

    issue_iid_from_branch(mr.sourceBranch)
  end

  def issue_iid_from_branch(source_branch)
    match_data = MR_ISSUE_PATTERN.match(source_branch)
    match_data&.named_captures&.fetch("issue_id")
  end

  def merge_request_issue_iids(merge_requests)
    merge_requests.flat_map { |mr| issue_references(mr) }
  end

  private

  def linked_work_item(mr)
    items = Array.wrap(mr.try(:linkedWorkItems))
    return if items.blank?
    return items.first if items.length == 1

    closing = items.select { |item| item.linkType == "CLOSES" }
    closing.first if closing.length == 1
  end

  def issue_project_full_path(mr)
    linked_work_item(mr)&.workItem&.namespace&.fullPath || mr.project.fullPath
  end

  # Placeholder for an issue that the GitLab token cannot read, such as a confidential issue
  def unavailable_issue(mr, iid)
    OpenStruct.new(
      iid: iid,
      webUrl: "#{GitlabClient.gitlab_instance_url}/#{issue_project_full_path(mr)}/-/issues/#{iid}",
      titleHtml: ERB::Util.html_escape(UNAVAILABLE_ISSUE_TITLE_HTML),
      milestone: nil,
      labels: OpenStruct.new(nodes: []),
      unavailable: true
    )
  end

  def issue_references(mr)
    issue_iid = issue_iid_from_mr(mr)
    return [] unless issue_iid

    project_full_path = issue_project_full_path(mr)

    refs = [{project_full_path: project_full_path, issue_iid: issue_iid}]

    if project_full_path.include?(SECURITY_SUBGROUP)
      refs << {
        project_full_path: project_full_path.sub(SECURITY_SUBGROUP, ""),
        issue_iid: issue_iid
      }
    end

    refs
  end
end
