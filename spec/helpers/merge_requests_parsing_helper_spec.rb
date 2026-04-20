# frozen_string_literal: true

require "rails_helper"

RSpec.describe MergeRequestsParsingHelper do
  include MergeRequestsParsingHelper

  let(:work_item_476653) { double(iid: "476653", namespace: double(fullPath: "gitlab-org/gitlab")) }
  let(:work_item_511343) { double(iid: "511343", namespace: double(fullPath: "gitlab-org/gitlab")) }

  def make_linked_work_item(work_item, link_type)
    double(workItem: work_item, linkType: link_type)
  end

  describe "#issue_iid_from_branch" do
    subject { issue_iid_from_branch(source_branch) }

    context "with iid in middle of branch name" do
      let(:source_branch) { "pedropombeiro/511343/update-sharding_key_id-on-project-runners" }

      it { is_expected.to eq "511343" }
    end

    context "with iid in beginning of branch name" do
      let(:source_branch) { "511343-pedropombeiro-update-sharding_key_id-on-project-runners" }

      it { is_expected.to eq "511343" }
    end

    context "with no iid in branch name" do
      let(:source_branch) { "j.castillo-master-patch-a0c9-docs" }

      it { is_expected.to be_nil }
    end
  end

  describe "#issue_iid_from_mr" do
    let(:mr) { double }

    subject { issue_iid_from_mr(mr) }

    before do
      allow(mr).to receive(:sourceBranch).and_return(source_branch)
      allow(mr).to receive(:try).with(:linkedWorkItems).and_return(linked_work_items)
    end

    context "with no linked work items" do
      let(:linked_work_items) { [] }

      context "with iid in middle of branch name" do
        let(:source_branch) { "pedropombeiro/511343/update-sharding_key_id-on-project-runners" }

        it { is_expected.to eq "511343" }
      end

      context "with iid in beginning of branch name" do
        let(:source_branch) { "511343-pedropombeiro-update-sharding_key_id-on-project-runners" }

        it { is_expected.to eq "511343" }
      end

      context "with no iid in branch name" do
        let(:source_branch) { "j.castillo-master-patch-a0c9-docs" }

        it { is_expected.to be_nil }
      end
    end

    context "with a single linked work item" do
      let(:source_branch) { "pedropombeiro/511343/update-sharding_key_id-on-project-runners" }

      context "with linkType CLOSES" do
        let(:linked_work_items) { [make_linked_work_item(work_item_476653, "CLOSES")] }

        it "prefers the work item iid over the branch iid" do
          is_expected.to eq "476653"
        end
      end

      context "with linkType MENTIONED" do
        let(:linked_work_items) { [make_linked_work_item(work_item_476653, "MENTIONED")] }

        it "prefers the work item iid over the branch iid" do
          is_expected.to eq "476653"
        end
      end

      context "with no iid in branch name" do
        let(:source_branch) { "j.castillo-master-patch-a0c9-docs" }
        let(:linked_work_items) { [make_linked_work_item(work_item_476653, "MENTIONED")] }

        it { is_expected.to eq "476653" }
      end
    end

    context "with multiple linked work items" do
      let(:source_branch) { "pedropombeiro/511343/update-sharding_key_id-on-project-runners" }

      context "with exactly one CLOSES" do
        let(:linked_work_items) do
          [
            make_linked_work_item(work_item_476653, "CLOSES"),
            make_linked_work_item(work_item_511343, "MENTIONED")
          ]
        end

        it "uses the CLOSES work item iid" do
          is_expected.to eq "476653"
        end
      end

      context "with multiple CLOSES" do
        let(:linked_work_items) do
          [
            make_linked_work_item(work_item_476653, "CLOSES"),
            make_linked_work_item(work_item_511343, "CLOSES")
          ]
        end

        it "falls back to branch iid" do
          is_expected.to eq "511343"
        end
      end

      context "with only MENTIONED" do
        let(:linked_work_items) do
          [
            make_linked_work_item(work_item_476653, "MENTIONED"),
            make_linked_work_item(work_item_511343, "MENTIONED")
          ]
        end

        it "falls back to branch iid" do
          is_expected.to eq "511343"
        end
      end
    end
  end

  describe "#issue_from_mr" do
    let(:mr) { double }
    let(:issue_511343) { double }
    let(:issue_476653) { double }
    let(:issues_by_iid) do
      {"511343" => issue_511343, "476653" => issue_476653}
    end

    subject { issue_from_mr(mr, issues_by_iid) }

    before do
      allow(mr).to receive(:sourceBranch).and_return(source_branch)
      allow(mr).to receive(:try).with(:linkedWorkItems).and_return(linked_work_items)
    end

    context "with no linked work items" do
      let(:linked_work_items) { [] }

      context "with iid in middle of branch name" do
        let(:source_branch) { "pedropombeiro/511343/update-sharding_key_id-on-project-runners" }

        it { is_expected.to eq issue_511343 }

        context "when issue is not known" do
          let(:source_branch) { "pedropombeiro/511344/update-sharding_key_id-on-project-runners" }

          it { is_expected.to be_nil }
        end
      end
    end

    context "with a single linked work item" do
      let(:source_branch) { "pedropombeiro/511343/update-sharding_key_id-on-project-runners" }
      let(:linked_work_items) { [make_linked_work_item(work_item_476653, "MENTIONED")] }

      it "resolves the linked work item's issue" do
        is_expected.to eq issue_476653
      end
    end
  end
end
