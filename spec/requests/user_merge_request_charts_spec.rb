require "rails_helper"
require_relative "../support/graphql_shared_contexts"

RSpec.describe "UserMergeRequestCharts", type: :request do
  include GitlabDashboard::Application.routes.url_helpers

  include_context "stub graphql client"

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
          bom = Date.current.beginning_of_month - offset.months
          eom = 1.month.after(bom)

          stub_request(:post, graphql_url)
            .with(body: hash_including(
              "operationName" => "GitlabClient__MonthlyMergeRequestsQuery",
              "variables" => {
                "username" => username,
                "mergedAfter" => bom.to_fs,
                "mergedBefore" => eom.to_fs
              }
            ))
            .to_return_json(body: monthly_mr_stats_body[offset])
        end
      end

      before do
        service = instance_double(FetchMergeRequestsService)
        response = double
        user_dto = double

        allow(service).to receive(:execute).and_return(response)
        allow(service).to receive(:parse_dto).with(response).and_return(user_dto)

        allow(user_dto).to receive(:first_merged_merge_requests_timestamp).and_return(1.year.ago)
        allow(user_dto).to receive(:merged_merge_requests_count).and_return(500)
        allow(user_dto).to receive(:merged_merge_requests_tttm).and_return(11597219.020233)

        allow(FetchMergeRequestsService).to receive(:new).with(username).and_return(service)
      end

      it "returns http success" do
        request

        expect(response).to have_http_status :success
      end

      it "responds to json by default" do
        request

        expect(response.content_type).to eq "application/json; charset=utf-8"
      end

      pending "Test JSON return value"

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
