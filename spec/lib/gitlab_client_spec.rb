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
end
