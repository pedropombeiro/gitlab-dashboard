# frozen_string_literal: true

module MergeRequestsParsingHelper
  MR_ISSUE_PATTERN = %r{[^\d]*(?<issue_id>\d+)[/-].+}i.freeze

  def issue_from_mr(mr, open_issues_by_iid)
    iid = issue_iid_from_mr(mr)
    open_issues_by_iid[iid]
  end

  def issue_iid_from_mr(mr)
    match_data = MR_ISSUE_PATTERN.match(mr.sourceBranch)
    match_data&.named_captures&.fetch("issue_id")
  end

  def merge_request_issue_iids(merge_requests)
    merge_requests.map do |mr|
      {
        project_full_path: mr.project.fullPath,
        issue_iid: issue_iid_from_mr(mr)
      }
    end
  end
end
