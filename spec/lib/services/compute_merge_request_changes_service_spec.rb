require "rails_helper"

RSpec.describe Services::ComputeMergeRequestChangesService do
  let_it_be(:graphql_url) { "https://example.gitlab.com/api/graphql" }
  let_it_be(:graphql_client) do
    ::Graphlient::Client.new(graphql_url, schema_path: file_fixture("gitlab_graphql_schema.json"))
  end

  let_it_be(:open_mrs_response_body) { YAML.load_file(file_fixture("open_merge_requests.yml"))["one"] }

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
          dto.merged_merge_requests.items << response.user.openMergeRequests.nodes.pop
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

    private

    def response
      client.fetch_open_merge_requests(assignee).tap do |response|
        response[:user] = response.response.data.user
        response.user[:mergedMergeRequests] = OpenStruct.new(nodes: [])
        response.user[:firstCreatedMergedMergeRequests] = OpenStruct.new(nodes: [])
        response.user[:allMergedMergeRequests] = OpenStruct.new(count: 0, totalTimeToMerge: 0)
      end
    end
  end
end
