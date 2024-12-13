# frozen_string_literal: true

module MergeRequestsParsingHelper
  MR_ISSUE_PATTERN = %r{[^\d]*(?<issue_id>\d+)[/-].+}i
  SECURITY_SUBGROUP = "/security"

  def issue_from_mr(mr, open_issues_by_iid)
    iid = issue_iid_from_mr(mr)
    open_issues_by_iid[iid]
  end

  def issue_iid_from_mr(mr)
    match_data = MR_ISSUE_PATTERN.match(mr.sourceBranch)
    match_data&.named_captures&.fetch("issue_id")
  end

  def merge_request_issue_iids(merge_requests)
    merge_requests.flat_map { |mr| issue_references(mr) }
  end

  private

  def issue_references(mr)
    refs = []

    refs << {
      project_full_path: mr.project.fullPath,
      issue_iid: issue_iid_from_mr(mr)
    }

    if mr.project.fullPath.include?(SECURITY_SUBGROUP)
      refs << {
        # Take into account MRs in security projects which refer to issues in the canonical project
        project_full_path: mr.project.fullPath.delete(SECURITY_SUBGROUP),
        issue_iid: issue_iid_from_mr(mr)
      }
    end

    refs
  end
end
