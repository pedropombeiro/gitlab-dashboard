require "rails_helper"

RSpec.describe MergeRequestsController, type: :controller do
  let_it_be(:graphql_url) { "https://gitlab.example.com/api/graphql" }
  let_it_be(:graphql_client) do
    ::Graphlient::Client.new(graphql_url, schema_path: file_fixture("gitlab_graphql_schema.json"))
  end

  before do
    allow(GitlabClient).to receive(:client).and_return(graphql_client)
  end

  describe "GET /index" do
    def perform_request
      get :index, params: params
    end

    subject(:request) { perform_request }

    context "when user is unknown" do
      before do
        stub_request(:post, graphql_url).to_return(status: 200, body: {data: {user: nil}}.to_json)
      end

      let(:params) { {assignee: "non-existent"} }

      it "returns http not_found" do
        request

        expect(response).to have_http_status(:not_found)
        expect(GitlabUser.find_by_username("non-existent")).to be_nil
      end
    end

    context "when user is known" do
      let(:username) { "user1" }
      let(:params) { {assignee: username} }
      let!(:user_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including("query" => a_string_matching(/user: /)))
          .to_return(status: 200, body: {data: {user: {username: username}}}.to_json)
      end

      it "returns http success and creates user with correct timestamp", :freeze_time do
        request

        expect(response).to have_http_status :success
        expect(GitlabUser.find_by_username(username)).to have_attributes(
          created_at: Time.current,
          updated_at: Time.current,
          contacted_at: Time.current
        )
      end

      it "responds to html by default" do
        request

        expect(response.content_type).to eq "text/html; charset=utf-8"
      end

      context "when called twice" do
        it "calls api twice" do
          # A second request is generates a second API call
          2.times { perform_request }

          expect(user_request_stub).to have_been_requested.twice
        end

        context "with cache enabled", :with_cache do
          it "only calls api once" do
            # A second request is served from the cache, and doesn't generate more API calls
            2.times { perform_request }

            expect(response).to have_http_status :success
            expect(user_request_stub).to have_been_requested.once
          end
        end
      end

      context "when assignee is not specified" do
        let(:params) { nil }

        it "returns network_authentication_required" do
          request

          expect(response).to have_http_status(:network_authentication_required)
          expect(GitlabUser.find_by_username(username)).to be_nil
        end

        context "when GITLAB_TOKEN is specified" do
          before do
            allow(Rails.application.credentials).to receive(:gitlab_token).and_return("secret-token")
          end

          it "redirects to assignee specified in GITLAB_TOKEN" do
            request

            expect(response).to redirect_to action: :index, assignee: username
            expect(GitlabUser.find_by_username(username)).to be_nil
          end
        end
      end
    end
  end

  describe "GET /list" do
    def perform_request
      get :list, params: params, format: format
    end

    subject(:request) { perform_request }

    let(:format) { nil }

    context "when user is known" do
      let_it_be(:open_mrs_body) { YAML.load_file(file_fixture("open_merge_requests.yml"))["one"].to_json }
      let_it_be(:merged_mrs_body) { YAML.load_file(file_fixture("merged_merge_requests.yml"))["one"].to_json }
      let_it_be(:issues_body) { YAML.load_file(file_fixture("issues.yml"))["one"].to_json }

      let(:username) { "pedropombeiro" }

      context "when assignee is unknown" do
        let(:params) { {assignee: "non-existent"} }

        it "returns not_found" do
          request

          expect(response).to have_http_status(:not_found)
          expect(GitlabUser.find_by_username("non-existent")).to be_nil
        end
      end

      context "when user exists", :freeze_time do
        let!(:user) { create(:gitlab_user, username: username, contacted_at: 1.day.ago) }
        let(:params) { {assignee: username, turbo: true} }

        let!(:open_mrs_request_stub) do
          stub_request(:post, graphql_url)
            .with(body: hash_including("query" => a_string_matching(/openMergeRequests: /)))
            .to_return(status: 200, body: open_mrs_body)
        end

        let!(:merged_mrs_request_stub) do
          stub_request(:post, graphql_url)
            .with(body: hash_including("query" => a_string_matching(/state: merged/)))
            .to_return(status: 200, body: merged_mrs_body)
        end

        let!(:issues_request_stub) do
          stub_request(:post, graphql_url)
            .with(body: hash_including("query" => a_string_matching(/project_\d:/)))
            .to_return(status: 200, body: issues_body)
        end

        it "returns http not_found" do
          request

          expect(response).to have_http_status(:not_found)
        end

        context "when session has user_id" do
          before do
            session[:user_id] = username
          end

          it "returns http success" do
            request

            expect(response).to have_http_status :success
          end

          it "responds to html by default" do
            request

            expect(response.content_type).to eq "text/html; charset=utf-8"
          end

          context "when called twice" do
            it "calls api twice" do
              # A second request is generates a second API call
              2.times { perform_request }

              expect(open_mrs_request_stub).to have_been_requested.twice
              expect(merged_mrs_request_stub).to have_been_requested.twice
              expect(issues_request_stub).to have_been_requested.twice
            end

            context "with cache enabled", :with_cache do
              it "only calls api once" do
                # A second request is served from the cache, and doesn't generate more API calls
                2.times { perform_request }

                expect(response).to have_http_status :success

                expect(open_mrs_request_stub).to have_been_requested.once
                expect(merged_mrs_request_stub).to have_been_requested.once
                expect(issues_request_stub).to have_been_requested.once
              end
            end
          end

          context "when json format provided in the params" do
            let(:format) { :json }

            it "responds to custom format" do
              request

              expect(response.content_type).to eq "application/json; charset=utf-8"
            end
          end

          context "with render_views" do
            render_views

            it "renders the actual template" do
              request

              expect(response.body).to include(%(<turbo-frame id="merge_requests_user_dto_#{username}">))
            end
          end

          context "when turbo param is missing" do
            let(:params) { {assignee: username} }

            it "redirects to index with the specified assignee" do
              request

              expect(response).to redirect_to action: :index, assignee: username
              expect(GitlabUser.find_by_username(username)).to have_attributes(
                contacted_at: Time.current
              )
            end
          end
        end
      end
    end
  end
end