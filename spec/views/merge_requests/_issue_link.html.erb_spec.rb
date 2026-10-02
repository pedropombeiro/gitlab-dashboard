# frozen_string_literal: true

require "rails_helper"

RSpec.describe "merge_requests/_issue_link" do
  subject(:rendered_html) do
    render partial: "merge_requests/issue_link", locals: {issue: issue}
    rendered
  end

  context "with an accessible issue" do
    let(:issue) do
      OpenStruct.new(
        iid: "631827",
        webUrl: "https://gitlab.com/gitlab-org/gitlab/-/issues/631827",
        titleHtml: "Persist metadata",
        milestone: nil,
        contextualLabels: []
      )
    end

    it "renders the issue link without the unavailable indicator" do
      expect(rendered_html).to include("#631827")
      expect(rendered_html).to include(%(href="https://gitlab.com/gitlab-org/gitlab/-/issues/631827"))
      expect(rendered_html).not_to include("bi-lock-fill")
    end
  end

  context "with an issue the GitLab token cannot access" do
    let(:issue) do
      OpenStruct.new(
        iid: "631827",
        webUrl: "https://gitlab.com/gitlab-org/gitlab/-/issues/631827",
        titleHtml: MergeRequestsParsingHelper::UNAVAILABLE_ISSUE_TITLE_HTML,
        milestone: nil,
        contextualLabels: [],
        unavailable: true
      )
    end

    it "renders the issue link with the unavailable indicator" do
      expect(rendered_html).to include("#631827")
      expect(rendered_html).to include(%(href="https://gitlab.com/gitlab-org/gitlab/-/issues/631827"))
      expect(rendered_html).to include("bi-lock-fill")
      expect(rendered_html).to include("cannot access this issue")
    end
  end

  context "without an issue" do
    let(:issue) { nil }

    it { is_expected.to include("N/A") }
  end
end
