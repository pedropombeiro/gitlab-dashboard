require "rails_helper"
require_relative "../support/graphql_shared_contexts"

RSpec.describe ComputeMergeRequestChangesService do
  include_context "stub graphql client"

  let_it_be(:open_mrs_response_body) { YAML.load_file(file_fixture("open_merge_requests.yml"))["one"] }
  let_it_be(:merged_mrs_response_body) { YAML.load_file(file_fixture("merged_merge_requests.yml"))["one"] }

  let(:issue_iids) do
    %w[
      503315 446287 506226 481411 502403 472974 481411 505703 457221 505810 32804 503748 442395 500447 502934 502431
      442395 497562 354756 506404
    ]
  end

  let(:client) { GitlabClient.new }
  let(:author) { "pedropombeiro" }
  let(:previous_dto) { ::UserDto.new(previous_response, author, type, issue_iids.to_h { |iid| [iid, new_issue] }) }
  let(:dto) { ::UserDto.new(new_response, author, type, issue_iids.to_h { |iid| [iid, new_issue] }) }
  let(:service) { described_class.new(type, previous_dto, dto) }

  subject(:execute) { service.execute }

  before do
    stub_request(:post, graphql_url)
      .with(body: hash_including("operationName" => "GitlabClient__OpenMergeRequestsQuery"))
      .to_return_json(body: open_mrs_response_body)
    stub_request(:post, graphql_url)
      .with(body: hash_including("operationName" => "GitlabClient__MergedMergeRequestsQuery"))
      .to_return_json(body: merged_mrs_response_body)
  end

  describe "open merge request changes" do
    let(:previous_response) { response }
    let(:new_response) { response }
    let(:type) { :open }
    let(:previous_mrs) { previous_response.user.openMergeRequests.nodes }

    it { is_expected.to be_empty }

    context "when MR label changes" do
      before do
        label = previous_mrs.first.labels.nodes.find { |label| label.title.start_with?("pipeline::tier-") }
        label.title = "pipeline::tier-2"
      end

      it { is_expected.not_to be_empty }

      it "contains notification for MR with change label" do
        is_expected.to match [
          a_hash_including(
            body: "changed to pipeline::tier-3\n\n!173741: Clean up runner audit log code",
            tag: "173741",
            type: :label_change,
            url: "https://gitlab.com/gitlab-org/gitlab/-/merge_requests/173741"
          )
        ]
      end

      context "when a second MR label changes" do
        before do
          label = previous_mrs.third.labels.nodes.find { |label| label.title.start_with?("pipeline::tier-") }
          label.title = "pipeline::tier-1"
        end

        it "contains notification for MR with change label" do
          is_expected.to match [
            a_hash_including(
              body: "changed to pipeline::tier-3\n\n!173741: Clean up runner audit log code",
              tag: "173741",
              type: :label_change,
              url: "https://gitlab.com/gitlab-org/gitlab/-/merge_requests/173741"
            ),
            a_hash_including(
              body: "changed to pipeline::tier-2\n\n!173789: Generate audit event per project association from runner",
              tag: "173789",
              timestamp: DateTime.parse("2024-11-27 10:51:59.000000000 +0000"),
              title: "An open merge request",
              type: :label_change,
              url: "https://gitlab.com/gitlab-org/gitlab/-/merge_requests/173789"
            )
          ]
        end
      end
    end
  end

  describe "merged merge request changes" do
    let(:previous_response) { response }
    let(:new_response) { response }
    let(:previous_mrs) { previous_response.user.mergedMergeRequests.nodes }
    let(:new_mrs) { new_response.user.mergedMergeRequests.nodes }
    let(:type) { :merged }
    let(:changed_mr_prev_version) { find_merge_request_with_labels(previous_mrs, mr_label_prefixes) }
    let(:changed_mr) { new_mrs.find { |new_mr| new_mr.iid == changed_mr_prev_version.iid } }

    it { is_expected.to be_empty }

    context "when MR pipeline label changes" do
      let(:mr_label_prefixes) { ["pipeline::tier-3"] }
      let(:changed_mr_prev_version_label) do
        changed_mr_prev_version.labels.nodes.find { |label| label.title.start_with?("pipeline::tier-") }
      end

      before do
        changed_mr_prev_version_label.title = "pipeline::tier-2"
      end

      it "does not generate notification" do
        is_expected.to be_empty
      end
    end

    context "when 'Pick into auto-deploy' label is added" do
      let(:mr_label_prefixes) { %w[workflow::production backend] }

      before do
        changed_mr.labels.nodes <<
          changed_mr.labels.nodes.last.dup.tap { |label| label.title = "Pick into auto-deploy" }
      end

      it "does not generate notification" do
        is_expected.to be_empty
      end
    end

    context "when MR workflow label changes" do
      let(:new_label_title) { nil }
      let(:changed_mr_label) { changed_mr.labels.nodes.find { |label| label.title.start_with?("workflow::") } }
      let(:changed_mr_prev_version_label) do
        changed_mr_prev_version.labels.nodes.find { |label| label.title.start_with?("workflow::") }
      end

      before do
        changed_mr_prev_version_label.title = prev_label_title
        changed_mr_label.title = new_label_title if new_label_title
      end

      context "with backend MR" do
        let(:mr_label_prefixes) { %w[workflow::production backend] }

        context "when workflow label changes from staging to production" do
          let(:prev_label_title) { "workflow::staging" }

          it "contains notification for MR with change label" do
            is_expected.to contain_exactly(
              a_hash_including(
                body: a_string_starting_with("changed to production\n\n!"),
                tag: an_instance_of(String),
                title: "A merged merge request",
                type: :label_change,
                url: an_instance_of(String)
              )
            )
          end

          context "and related issue is closed" do
            let(:issue_state) { "closed" }

            before do
              dto.merged_merge_requests.items
                .find { |mr| mr.iid == changed_mr_prev_version.iid }
                .issue.state = issue_state
            end

            it "does not generate notification" do
              is_expected.to be_empty
            end
          end
        end
      end

      context "with documentation MR" do
        let(:mr_label_prefixes) { %w[workflow::post-deploy-db-production documentation !backend] }

        context "when workflow label changes to from staging-canary to canary" do
          let(:prev_label_title) { "workflow::staging-canary" }
          let(:new_label_title) { "workflow::canary" }

          it "does not generate notification" do
            is_expected.to be_empty
          end
        end

        context "when workflow label changes from post-deploy-db-staging to post-deploy-db-production" do
          let(:prev_label_title) { "workflow::post-deploy-db-staging" }
          let(:new_label_title) { "workflow::post-deploy-db-production" }

          it "contains notification for MR with change label" do
            is_expected.to contain_exactly(
              a_hash_including(
                body: a_string_starting_with("changed to post-deploy-db-production\n\n!"),
                tag: an_instance_of(String),
                title: "A merged merge request",
                type: :label_change,
                url: an_instance_of(String)
              )
            )
          end
        end
      end

      context "when MR workflow::post-db-deploy-* label changes" do
        let(:mr_label_prefixes) { %w[workflow::post-deploy-db-production] }
        let(:prev_label_title) { "workflow::post-db-deploy-staging" }

        specify do
          expect(changed_mr_prev_version.labels.nodes.find { |label| label.title.start_with?("database") }).to be_nil
        end

        it "does not generate notification" do
          is_expected.to be_empty
        end

        context "and MR is labeled with database" do
          let(:mr_label_prefixes) { %w[workflow::post-deploy-db-production database] }

          it "contains notification for MR with change label" do
            is_expected.to contain_exactly(
              a_hash_including(
                body: a_string_starting_with("changed to post-deploy-db-production\n\n!"),
                tag: an_instance_of(String),
                title: "A merged merge request",
                type: :label_change,
                url: an_instance_of(String)
              )
            )
          end
        end
      end
    end

    context "when an MR is merged" do
      before do
        dto.merged_merge_requests.items << response.user.openMergeRequests.nodes.delete(merged_mr)
      end

      let(:merged_mr) { response.user.openMergeRequests.nodes.last }

      it "contains notification for merged MR" do
        is_expected.to include(
          a_hash_including(
            body: "!173007: Save runner taggings to shard table",
            tag: "173007",
            timestamp: DateTime.parse("2024-11-22T14:44:47Z"),
            title: "A merge request was merged",
            type: :merge_request_merged,
            url: "https://gitlab.com/gitlab-org/gitlab/-/merge_requests/173007"
          )
        )
      end
    end

    private

    def find_merge_request_with_labels(merge_requests, mr_label_prefixes)
      merge_requests.find do |mr|
        mr_label_prefixes.all? do |prefix|
          negate = prefix.start_with?("!")
          prefix.delete_prefix!("!") if negate

          contains_label = mr.labels.nodes.any? { |label| label.title.start_with?(prefix) }

          negate ? !contains_label : contains_label
        end
      end
    end
  end

  private

  def response
    client.fetch_open_merge_requests(author).tap do |response|
      response[:user] = response.response.data.user

      merged_mrs_response = client.fetch_merged_merge_requests(author)
      user2 = merged_mrs_response.response.data.user
      response.user.mergedMergeRequests = user2.mergedMergeRequests
      response.user.allMergedMergeRequests = user2.allMergedMergeRequests
      response.user.firstCreatedMergedMergeRequests = user2.firstCreatedMergedMergeRequests
    end
  end

  def new_issue
    OpenStruct.new(
      state: "opened",
      labels: OpenStruct.new(nodes: []),
      contextualLabels: OpenStruct.new(nodes: [])
    )
  end
end
