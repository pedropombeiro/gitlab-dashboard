# frozen_string_literal: true

require "rails_helper"

RSpec.describe MergeRequestsParsingHelper do
  include MergeRequestsParsingHelper

  describe "#issue_iid_from_mr" do
    let(:mr) { double }

    subject { issue_iid_from_mr(mr) }

    before do
      allow(mr).to receive(:sourceBranch).and_return(source_branch)
    end

    context "with iid in middle of branch name" do
      let(:source_branch) { "pedropombeiro/511343/update-sharding_key_id-on-project-runners" }
      let(:expected_issue_iid) { "511343" }

      it "extracts issue iid from MR branch name" do
        is_expected.to eq expected_issue_iid
      end
    end

    context "with iid in beginning of branch name" do
      let(:source_branch) { "511343-pedropombeiro-update-sharding_key_id-on-project-runners" }
      let(:expected_issue_iid) { "511343" }

      it "extracts issue iid from MR branch name" do
        is_expected.to eq expected_issue_iid
      end
    end

    context "with no iid in branch name" do
      let(:source_branch) { "j.castillo-master-patch-a0c9-docs" }
      let(:expected_issue_iid) { nil }

      it "does not extract issue iid from MR branch name" do
        is_expected.to be_nil
      end
    end
  end

  describe "#issue_from_mr" do
    let(:mr) { double }
    let(:issue_511343) { double }
    let(:issues_by_iid) do
      {"511343" => issue_511343}
    end

    subject { issue_from_mr(mr, issues_by_iid) }

    before do
      allow(mr).to receive(:sourceBranch).and_return(source_branch)
    end

    context "with iid in middle of branch name" do
      let(:source_branch) { "pedropombeiro/511343/update-sharding_key_id-on-project-runners" }

      it "extracts issue from MR branch name" do
        is_expected.to eq issue_511343
      end

      context "when issue is not known" do
        let(:source_branch) { "pedropombeiro/511344/update-sharding_key_id-on-project-runners" }

        it "extracts issue from MR branch name" do
          is_expected.to be_nil
        end
      end
    end
  end
end
