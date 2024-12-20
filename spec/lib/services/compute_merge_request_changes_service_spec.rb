require "rails_helper"

RSpec.describe Services::ComputeMergeRequestChangesService do
  let_it_be(:graphql_url) { "https://example.gitlab.com/api/graphql" }
  let_it_be(:graphql_client) do
    ::Graphlient::Client.new(graphql_url, schema_path: file_fixture("gitlab_graphql_schema.json"))
  end

  let_it_be(:open_mrs_response_body) { YAML.load_file(file_fixture("open_merge_requests.yml"))["one"] }
  let_it_be(:merged_mrs_response_body) { YAML.load_file(file_fixture("merged_merge_requests.yml"))["one"] }

  let(:client) { GitlabClient.new }
  let(:assignee) { "pedropombeiro" }
  let(:previous_dto) { ::UserDto.new(previous_response, assignee, {}) }
  let(:dto) { ::UserDto.new(new_response, assignee, {}) }
  let(:service) { described_class.new(previous_dto, dto) }

  subject(:execute) { service.execute }

  before do
    allow(GitlabClient).to receive(:client).and_return(graphql_client)

    stub_request(:post, graphql_url)
      .with(body: hash_including("query" => a_string_matching(/openMergeRequests: /)))
      .to_return(
        status: 200,
        body: open_mrs_response_body.to_json
      )
    stub_request(:post, graphql_url)
      .with(body: hash_including("query" => a_string_matching(/mergedMergeRequests: /)))
      .to_return(
        status: 200,
        body: merged_mrs_response_body.to_json
      )
  end

  describe "open merge request changes" do
    let(:previous_response) { response }
    let(:new_response) { response }

    it { is_expected.to be_empty }

    context "when MR label changes" do
      before do
        label = previous_response.user.openMergeRequests.nodes.first.labels.nodes.find do |label|
          label.title.start_with?("pipeline::tier-")
        end

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
          label = previous_response.user.openMergeRequests.nodes.third.labels.nodes.find do |label|
            label.title.start_with?("pipeline::tier-")
          end

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

      context "when an MR is merged" do
        before do
          dto.merged_merge_requests.items << response.user.openMergeRequests.nodes.delete(merged_mr)
        end

        let(:merged_mr) do
          response.user.openMergeRequests.nodes.last
        end

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
    end
  end

  describe "merged merge request changes" do
    let(:previous_response) { response }
    let(:new_response) { response }

    it { is_expected.to be_empty }

    context "when MR pipeline label changes" do
      before do
        mr = find_merge_request_with_labels(previous_response.user.mergedMergeRequests.nodes, "pipeline::tier-3")
        label = mr.labels.nodes.find { |label| label.title.start_with?("pipeline::tier-") }
        label.title = "pipeline::tier-2"
      end

      it { is_expected.to be_empty }
    end

    context "when MR workflow label changes" do
      before do
        mr = find_merge_request_with_labels(previous_response.user.mergedMergeRequests.nodes, "workflow::production")
        label = mr.labels.nodes.find { |label| label.title.start_with?("workflow::production") }
        label.title = "workflow::staging"
      end

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
    end

    context "when MR workflow::post-db-deploy-* label changes" do
      let(:changed_mr) do
        find_merge_request_with_labels(
          previous_response.user.mergedMergeRequests.nodes, "workflow::post-deploy-db-production"
        )
      end

      before do
        label = changed_mr.labels.nodes.find { |label| label.title.start_with?("workflow::post-deploy-db") }
        label.title = "workflow::post-db-deploy-staging"
      end

      specify do
        expect(changed_mr.labels.nodes.find { |label| label.title.start_with?("database") }).to be_nil
      end

      it { is_expected.to be_empty }

      context "and MR is labelled with database" do
        let(:changed_mr) do
          find_merge_request_with_labels(
            previous_response.user.mergedMergeRequests.nodes, "workflow::post-deploy-db-production", "database"
          )
        end

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

    private

    def find_merge_request_with_labels(merge_requests, *label_prefixes)
      merge_requests.find do |mr|
        label_prefixes.all? do |prefix|
          mr.labels.nodes.any? do |label|
            label.title.start_with?(prefix)
          end
        end
      end
    end
  end

  private

  def response
    client.fetch_open_merge_requests(assignee).tap do |response|
      response[:user] = response.response.data.user

      merged_mrs_response = client.fetch_merged_merge_requests(assignee)
      user2 = merged_mrs_response.response.data.user
      response.user.mergedMergeRequests = user2.mergedMergeRequests
      response.user.allMergedMergeRequests = user2.allMergedMergeRequests
      response.user.firstCreatedMergedMergeRequests = user2.firstCreatedMergedMergeRequests
    end
  end
end
