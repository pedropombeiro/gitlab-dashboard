# frozen_string_literal: true

module MergeRequestsParsingHelper
  MR_ISSUE_PATTERN = %r{\b(?<issue_id>\d+)[/-].+}i
  SECURITY_SUBGROUP = "/security"

  def issue_from_mr(mr, issues_by_iid)
    iid = issue_iid_from_mr(mr)
    issues_by_iid[iid]
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

  def issue_references(mr)
    issue_iid = issue_iid_from_mr(mr)
    return [] unless issue_iid

    work_item = linked_work_item(mr)&.workItem
    project_full_path = work_item&.namespace&.fullPath || mr.project.fullPath

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
