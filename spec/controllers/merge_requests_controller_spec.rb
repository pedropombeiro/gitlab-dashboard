require "rails_helper"

RSpec.describe MergeRequestsController, type: :controller do
  let_it_be(:fixtures_path) { Rails.root.join("spec/support/fixtures") }
  let_it_be(:gitlab_instance_url) { "https://gitlab.com" }
  let_it_be(:graphql_url) { "#{gitlab_instance_url}/api/graphql" }
  let_it_be(:graphql_client) do
    ::Graphlient::Client.new(
      "#{gitlab_instance_url}/api/graphql",
      schema_path: fixtures_path.join("gitlab_graphql_schema.json")
    )
  end

  before do
    allow(GitlabClient).to receive(:client).and_return(graphql_client)
  end

  describe "GET /index" do
    context "when user is unknown" do
      before do
        stub_request(:post, graphql_url).to_return(status: 200, body: {data: {user: nil}}.to_json)
      end

      it "returns http not_found" do
        get :index, params: {assignee: "non-existent"}

        expect(response).to have_http_status(:not_found)
        expect(GitlabUser.find_by_username("non-existent")).to be_nil
      end
    end
  end
end
