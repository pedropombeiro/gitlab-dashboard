require "rails_helper"

RSpec.describe GitlabClient do
  let_it_be(:fixtures_path) { Rails.root.join("spec/support/fixtures") }
  let_it_be(:gitlab_instance_url) { "https://gitlab.com" }
  let_it_be(:graphql_client) do
    ::Graphlient::Client.new(
      "#{gitlab_instance_url}/api/graphql",
      schema_path: fixtures_path.join("gitlab_graphql_schema.json")
    )
  end

  let(:client) { described_class.new }

  describe "#fetch_user" do
    let(:username) { "pedropombeiro" }

    subject(:fetch_user) do
      client.fetch_user(username)
    end

    before do
      allow(client).to receive(:client).and_return(graphql_client)

      user_requests = YAML.load_file(fixtures_path.join("user_requests.yml"))
      stub_request(:post, "#{gitlab_instance_url}/api/graphql").to_return(
        status: 200,
        body: user_requests[username].to_json
      )
    end

    it "returns the user data" do
      expect(fetch_user.data).to be_truthy
      expect(fetch_user.data.user).to have_attributes(
        "__typename" => "UserCore",
        "username" => "pedropombeiro",
        "avatarUrl" => "/uploads/-/system/user/avatar/1388762/avatar.png",
        "webUrl" => "https://gitlab.com/pedropombeiro"
      )
    end
  end

  describe "#fetch_issues" do
    let(:merged_mr_issues) do
      [{project_full_path: "gitlab-org/gitlab", issue_iid: "505810"}]
    end

    let(:open_mr_issues) do
      [
        {project_full_path: "gitlab-org/gitlab-runner", issue_iid: "32804"},
        {project_full_path: "gitlab-org/gitlab", issue_iid: "506226"}
      ]
    end

    subject(:fetch_issues) do
      client.fetch_issues(merged_mr_issues, open_mr_issues)
    end

    before do
      allow(client).to receive(:client).and_return(graphql_client)

      issues = YAML.load_file(fixtures_path.join("issues.yml"))
      stub_request(:post, "#{gitlab_instance_url}/api/graphql").to_return(
        status: 200,
        body: issues["one"].to_json
      )
    end

    it "returns an array with the processed issue data" do
      expect(fetch_issues).to match(an_array_matching([
        an_object_having_attributes(
          "iid" => "32804",
          "webUrl" => "https://gitlab.com/gitlab-org/gitlab-runner/-/issues/32804"
        ),
        an_object_having_attributes(
          "iid" => "506226",
          "webUrl" => "https://gitlab.com/gitlab-org/gitlab/-/issues/506226"
        ),
        an_object_having_attributes(
          "iid" => "505810",
          "webUrl" => "https://gitlab.com/gitlab-org/gitlab/-/issues/505810"
        )
      ]))
    end
  end

  describe "#fetch_open_merge_requests" do
    let(:username) { "pedropombeiro" }
    let(:result_as_hash) { openstruct_to_hash(fetch_open_merge_requests) }

    subject(:fetch_open_merge_requests) do
      client.fetch_open_merge_requests(username)
    end

    before do
      allow(client).to receive(:client).and_return(graphql_client)

      response = YAML.load_file(fixtures_path.join("open_merge_requests.yml"))
      stub_request(:post, "#{gitlab_instance_url}/api/graphql").to_return(
        status: 200,
        body: response["one"].to_json
      )
    end

    it "returns the merge request data", :freeze_time do
      common_mr_attrs = {
        project: a_hash_including(fullPath: "gitlab-org/gitlab"),
        reviewers: {nodes: an_instance_of(Array)},
        assignees: {nodes: an_instance_of(Array)},
        labels: {nodes: an_instance_of(Array)},
        blockingMergeRequests: {visibleMergeRequests: an_instance_of(Array)}
      }

      expect(fetch_open_merge_requests).to be_truthy
      expect(result_as_hash).to match(
        updated_at: Time.current,
        user: {
          openMergeRequests: {
            nodes: [
              a_hash_including(iid: "173741", **common_mr_attrs),
              a_hash_including(iid: "174004", **common_mr_attrs),
              a_hash_including(iid: "173789", **common_mr_attrs),
              a_hash_including(iid: "173874", **common_mr_attrs),
              a_hash_including(iid: "173916", **common_mr_attrs),
              a_hash_including(iid: "173886", **common_mr_attrs),
              a_hash_including(iid: "173885", **common_mr_attrs,
                blockingMergeRequests: {visibleMergeRequests: [iid: "173886", state: "opened"]}),
              a_hash_including(iid: "173639", **common_mr_attrs),
              a_hash_including(iid: "171848", **common_mr_attrs,
                blockingMergeRequests: {visibleMergeRequests: [{iid: "172422", state: "merged"}, {iid: "172698", state: "closed"}]}),
              a_hash_including(iid: "173007", **common_mr_attrs)
            ]
          }
        }
      )
    end
  end

  private

  def openstruct_to_hash(object, hash = {})
    case object
    when OpenStruct
      object.each_pair do |key, value|
        hash[key] = openstruct_to_hash(value)
      end
      hash
    when Array
      object.map { |v| openstruct_to_hash(v) }
    else object
    end
  end
end