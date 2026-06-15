# frozen_string_literal: true

require "rails_helper"

RSpec.describe MergeRequestPresenter do
  subject(:presenter) { described_class.new(merge_request) }

  describe "#approvals_tooltip" do
    subject(:tooltip) { presenter.approvals_tooltip }

    def rule(name:, type:, approved:, approvals_required: 1, eligible_approvers: [])
      OpenStruct.new(
        name: name,
        type: type,
        approved: approved,
        approvalsRequired: approvals_required,
        eligibleApprovers: eligible_approvers
      )
    end

    def approvers(count)
      Array.new(count) { |i| OpenStruct.new(username: "user#{i}") }
    end

    def build_mr(approvals_left:, rules:)
      approval_state = rules.nil? ? nil : OpenStruct.new(rules: rules)
      OpenStruct.new(approvalsLeft: approvals_left, approvalState: approval_state)
    end

    context "with a blocking code owner rule" do
      let(:merge_request) do
        build_mr(
          approvals_left: 1,
          rules: [rule(name: "/spec/", type: "CODE_OWNER", approved: false)]
        )
      end

      it "shows the count header and lists the code owner rule" do
        expect(tooltip).to include("<strong>1 approval missing</strong>")
        expect(tooltip).to include("Code owner approval needed:")
        expect(tooltip).to include("<li><code>/spec/</code></li>")
      end
    end

    context "with eligible approver pool and multiple required approvals" do
      let(:merge_request) do
        build_mr(
          approvals_left: 2,
          rules: [
            rule(name: "/spec/", type: "CODE_OWNER", approved: false, approvals_required: 2, eligible_approvers: approvers(153))
          ]
        )
      end

      it "shows the required count and pool size next to the rule" do
        expect(tooltip).to include("<li><code>/spec/</code>")
        expect(tooltip).to include("needs 2, 153 eligible approvers")
      end
    end

    context "with a single eligible approver" do
      let(:merge_request) do
        build_mr(
          approvals_left: 1,
          rules: [rule(name: "/spec/", type: "CODE_OWNER", approved: false, eligible_approvers: approvers(1))]
        )
      end

      it "pluralizes the pool size and omits the needs count" do
        expect(tooltip).to include("(1 eligible approver)")
        expect(tooltip).not_to include("needs")
      end
    end

    context "with multiple blocking code owner rules" do
      let(:merge_request) do
        build_mr(
          approvals_left: 2,
          rules: [
            rule(name: "/spec/", type: "CODE_OWNER", approved: false),
            rule(name: "/app/", type: "CODE_OWNER", approved: false)
          ]
        )
      end

      it "lists each code owner rule as a separate item" do
        expect(tooltip).to include("<strong>2 approvals missing</strong>")
        expect(tooltip).to include("<li><code>/spec/</code></li>")
        expect(tooltip).to include("<li><code>/app/</code></li>")
      end
    end

    context "when a code owner rule is already approved" do
      let(:merge_request) do
        build_mr(
          approvals_left: 1,
          rules: [
            rule(name: "/spec/", type: "CODE_OWNER", approved: true),
            rule(name: "All Members", type: "ANY_APPROVER", approved: false)
          ]
        )
      end

      it "does not list the satisfied code owner rule" do
        expect(tooltip).to eq "<strong>1 approval missing</strong>"
      end
    end

    context "with only an any-approver rule" do
      let(:merge_request) do
        build_mr(
          approvals_left: 2,
          rules: [rule(name: "All Members", type: "ANY_APPROVER", approved: false)]
        )
      end

      it { is_expected.to eq "<strong>2 approvals missing</strong>" }
    end

    context "when approvalState is nil" do
      let(:merge_request) { build_mr(approvals_left: 1, rules: nil) }

      it { is_expected.to eq "<strong>1 approval missing</strong>" }
    end

    context "when rules is empty" do
      let(:merge_request) { build_mr(approvals_left: 3, rules: []) }

      it { is_expected.to eq "<strong>3 approvals missing</strong>" }
    end
  end
end
