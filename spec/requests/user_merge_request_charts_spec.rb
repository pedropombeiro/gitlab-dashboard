require "rails_helper"

RSpec.describe "UserMergeRequestCharts", type: :request do
  include GitlabDashboard::Application.routes.url_helpers

  let_it_be(:graphql_url) { "https://gitlab.example.com/api/graphql" }
  let_it_be(:graphql_client) do
    ::Graphlient::Client.new(graphql_url, schema_path: file_fixture("gitlab_graphql_schema.json"))
  end

  before do
    allow(GitlabClient).to receive(:client).and_return(graphql_client)
    stub_env("GITLAB_URL", "https://gitlab.example.com")
  end

  describe "GET /monthly_merged_merge_request_stats" do
    def perform_request
      get monthly_merged_merge_request_stats_path(**params)
    end

    subject(:request) { perform_request }

    let_it_be(:monthly_mr_stats_body) do
      YAML.load_file(file_fixture("monthly_merged_merge_request_stats.yml"))["one"]
    end

    let(:username) { "pedropombeiro" }

    context "when user exists", :freeze_time do
      let(:params) { {assignee: username} }

      let!(:merged_mrs_request_stubs) do
        12.times.map do |offset|
          bom = Date.new(2024, 12, 31).beginning_of_month - offset.months
          eom = 1.month.after(bom)

          stub_request(:post, graphql_url)
            .with(body: hash_including(
              "query" => a_string_including("monthlyMergedMergeRequests"),
              "variables" => {
                "username" => username,
                "mergedAfter" => bom.to_fs,
                "mergedBefore" => eom.to_fs
              }
            ))
            .to_return(status: 200, body: monthly_mr_stats_body[offset].to_json)
        end
      end

      it "returns http success" do
        request

        expect(response).to have_http_status :success
      end

      it "responds to json by default" do
        request

        expect(response.content_type).to eq "application/json; charset=utf-8"
      end

      context "when called twice" do
        it "calls api twice" do
          # A second request generates a second API call
          2.times { perform_request }

          merged_mrs_request_stubs.each { |stub| expect(stub).to have_been_requested.twice }
        end

        context "with cache enabled", :with_cache do
          it "only calls api once" do
            # A second request is served from the cache, and doesn't generate more API calls
            2.times { perform_request }

            expect(response).to have_http_status :success

            merged_mrs_request_stubs.each { |stub| expect(stub).to have_been_requested.once }
          end
        end
      end
    end
  end
end
