require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  before do
    stub_const("GitlabDashboard::Application::GIT_RELEASE_TAG", release_tag)
    stub_const("GitlabDashboard::Application::GIT_COMMIT_SHA", commit_sha)
  end

  let(:release_tag) { "v2026.09.01.1" }
  let(:commit_sha) { "3b92a63efc6ddf6e06ccaa5c346045196569dc6c" }

  it "links to the release and identifies it in the tooltip" do
    expect(helper.git_repo_url).to eq(
      "https://github.com/pedropombeiro/gitlab-dashboard/releases/tag/v2026.09.01.1"
    )
    expect(helper.git_repo_link_title).to eq("Release v2026.09.01.1")
  end

  context "when the release tag is unavailable" do
    let(:release_tag) { nil }

    it "links to the commit and identifies its short SHA in the tooltip" do
      expect(helper.git_repo_url).to eq(
        "https://github.com/pedropombeiro/gitlab-dashboard/commit/3b92a63efc6ddf6e06ccaa5c346045196569dc6c"
      )
      expect(helper.git_repo_link_title).to eq("Commit 3b92a63")
    end
  end

  context "when Docker metadata contains null placeholders" do
    let(:release_tag) { "null" }
    let(:commit_sha) { "null" }

    it "links to the repository without a tooltip" do
      expect(helper.git_repo_url).to eq("https://github.com/pedropombeiro/gitlab-dashboard")
      expect(helper.git_repo_link_title).to be_nil
    end
  end

  context "when the release tag is a null placeholder" do
    let(:release_tag) { "null" }

    it "falls back to the commit" do
      expect(helper.git_repo_url).to end_with("/commit/#{commit_sha}")
      expect(helper.git_repo_link_title).to eq("Commit 3b92a63")
    end
  end
end
