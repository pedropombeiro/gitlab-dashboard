require "rails_helper"
require_relative "../support/graphql_shared_contexts"

RSpec.describe GroupReviewersDto do
  include_context "stub graphql client"

  let_it_be(:group_reviewers_response_body) { YAML.load_file(file_fixture("group_reviewers.yml")) }

  let(:group_path) { "gitlab-org" }
  let(:graphql_response_body) { group_reviewers_response_body["verify"] }

  # The DTO consumes the response after GitlabClient has folded activeReviews
  # into a count, so go through the client rather than the raw fixture.
  let(:response) { GitlabClient.new.fetch_group_reviewers(group_path) }

  subject(:dto) { described_class.new(response, group_path) }

  before do
    stub_request(:post, graphql_url)
      .with(body: hash_including("operationName" => "GitlabClient__GroupReviewersQuery"))
      .to_return_json(body: graphql_response_body)

    allow_any_instance_of(LocationLookupService).to receive(:fetch_timezones)
    allow_any_instance_of(LocationLookupService).to receive(:fetch_timezone)
  end

  it "skips members without a user and bots" do
    usernames = dto.reviewers.map(&:username)

    expect(usernames).to include("rkadam3", "pedropombeiro")
    expect(usernames).not_to include("gitlab-infra-mgmt-bot", "employment-bot")
    expect(usernames).to all(be_present)
  end

  it "warms up the timezone cache with the locations of visible users" do
    expect_any_instance_of(LocationLookupService).to receive(:fetch_timezones)
      .with(a_collection_including("Mumbai, India", "Vancouver, Canada"))

    dto
  end

  context "when a reviewer has no recorded activity" do
    let(:graphql_response_body) do
      group_reviewers_response_body["verify"].deep_dup.tap do |body|
        reviewer = body.dig("data", "group", "groupMembers", "nodes").find do |member|
          member.dig("user", "username") == "rkadam3"
        end
        reviewer["user"]["lastActivityOn"] = nil
      end
    end

    it "treats the reviewer as inactive" do
      reviewer = dto.reviewers.find { |candidate| candidate.username == "rkadam3" }

      expect(reviewer.lastActivityOn).to be_nil
      expect(dto.send(:inactive?, reviewer)).to be(true)
    end
  end
end
