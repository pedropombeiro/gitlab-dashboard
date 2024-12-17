require "rails_helper"

RSpec.describe MergeRequestsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  let_it_be(:graphql_url) { "https://gitlab.example.com/api/graphql" }
  let_it_be(:graphql_client) do
    ::Graphlient::Client.new(graphql_url, schema_path: file_fixture("gitlab_graphql_schema.json"))
  end

  before do
    allow(GitlabClient).to receive(:client).and_return(graphql_client)
    stub_env("GITLAB_URL", "https://gitlab.example.com")
  end

  describe "GET /index" do
    def perform_request
      get :index, params: params
    end

    subject(:request) { perform_request }

    context "when user is unknown" do
      before do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "query" => a_string_including("user("),
            "variables" => {username: "non-existent"}
          ))
          .to_return(status: :ok, body: {data: {user: nil}}.to_json)
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
      let(:user_response_body) do
        {
          data: {
            user: {
              username: username,
              avatarUrl: "/images/avatar.png",
              webUrl: "https://gitlab.example.com/#{username}"
            }
          }
        }.to_json
      end

      let!(:user_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "query" => a_string_including("user("),
            "variables" => {username: username}
          ))
          .to_return(status: :ok, body: user_response_body)
      end

      it "returns http success and creates user with correct timestamp", :freeze_time do
        expect(GitlabUser.find_by_username(username)).to be_nil

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
          # A second request generates a second API call
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

      context "with render_views" do
        render_views

        it "renders the actual template" do
          request

          expect(response).to have_http_status(:ok)
          expect(response).to render_template("layouts/application")
          expect(response).to render_template("merge_requests/_user_image")

          # Includes header with link to user's merge requests
          expect(response.body).to include(
            %(<a class="fw-light" href="https://gitlab.example.com/#{username}">#{username}</a>)
          )
          # and user's avatar
          expect(response.body).to include(
            %(<img class="rounded float-left" src="https://gitlab.example.com/images/avatar.png" width="24" height="24" />)
          )
          # Includes turbo frame with merge requests list
          expect(response.body).to include(%(src="#{merge_requests_list_path(username, turbo: true)}"))

          # Includes refresh button on x-small views
          expect(response.body).to include(
            %(<form class="button_to" method="get" action="#{merge_requests_path(username)}">)
          )
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

          let!(:user_request_stub) do
            stub_request(:post, graphql_url)
              .with(body: hash_including(
                "query" => a_string_including("user: currentUser"),
                "variables" => {}
              ))
              .to_return(status: :ok, body: user_response_body)
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

    context "when assignee is unknown" do
      before do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "query" => a_string_including("user("),
            "variables" => {username: "non-existent"}
          ))
          .to_return(status: :ok, body: {data: {user: nil}}.to_json)
      end

      let(:params) { {assignee: "non-existent"} }

      it "returns http not_found" do
        request

        expect(response).to have_http_status(:not_found)
        expect(GitlabUser.find_by_username("non-existent")).to be_nil
      end
    end

    context "when assignee is known" do
      let_it_be(:issues0_body) { YAML.load_file(file_fixture("issues.yml"))["project_0"].to_json }
      let_it_be(:issues1_body) { YAML.load_file(file_fixture("issues.yml"))["project_1"].to_json }
      let_it_be(:issues2_body) { YAML.load_file(file_fixture("issues.yml"))["project_2"].to_json }

      let(:open_mrs) { YAML.load_file(file_fixture("open_merge_requests.yml"))["one"] }
      let(:merged_mrs) { YAML.load_file(file_fixture("merged_merge_requests.yml"))["one"] }
      let(:username) { "pedropombeiro" }

      context "when user exists" do
        let!(:user) { create(:gitlab_user, username: username, contacted_at: 1.day.ago) }
        let(:params) { {assignee: username, turbo: true} }

        let!(:user_request_stub) do
          stub_request(:post, graphql_url)
            .with(body: hash_including(
              "query" => a_string_including("user("),
              "variables" => {username: username}
            ))
            .to_return(status: :ok, body: {data: {user: {username: username, avatarUrl: "", webUrl: ""}}}.to_json)
        end

        let!(:open_mrs_request_stub) do
          stub_request(:post, graphql_url)
            .with(body: hash_including(
              "query" => a_string_including("openMergeRequests: "),
              "variables" => hash_including(
                "username" => username,
                "activeReviewsAfter" => an_instance_of(String)
              )
            ))
            .to_return(status: :ok, body: open_mrs.to_json)
        end

        let!(:merged_mrs_request_stub) do
          stub_request(:post, graphql_url)
            .with(body: hash_including(
              "query" => a_string_including("mergedMergeRequests: authoredMergeRequests"),
              "variables" => {"username" => username}
            ))
            .to_return(status: :ok, body: merged_mrs.to_json)
        end

        let!(:issues_request_stub) do
          stub_request(:post, graphql_url)
            .with(body: hash_including(
              "query" => a_string_including(%[issues(iids: $issueIids)]),
              "variables" => hash_including(
                "projectFullPath" => "gitlab-org/gitlab",
                "issueIids" => an_array_matching(%w[
                  503315 446287 506226 481411 506385 502403 472974 506404 505703 457221 505810 503748 442395 500447
                  502934 502431 497562 354756
                ])
              )
            ))
            .to_return(status: :ok, body: issues0_body)
          stub_request(:post, graphql_url)
            .with(body: hash_including(
              "query" => a_string_including(%[issues(iids: $issueIids)]),
              "variables" => {
                "projectFullPath" => "gitlab-org/security/gitlab-runner",
                "issueIids" => %w[32804]
              }
            ))
            .to_return(status: :ok, body: issues1_body)
          stub_request(:post, graphql_url)
            .with(body: hash_including(
              "query" => a_string_including(%[issues(iids: $issueIids)]),
              "variables" => {
                "projectFullPath" => "gitlab-org/gitlab-runner",
                "issueIids" => %w[32804]
              }
            ))
            .to_return(status: :ok, body: issues2_body)
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
            # A second request generates a second API call
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

            context "and merge request has been opened in between" do
              let!(:subscription) { create(:web_push_subscription, gitlab_user: user) }

              it "does not send web push notification" do
                open_mr_nodes = open_mrs.dig(*%w[data user openMergeRequests nodes])
                opened_mr = open_mr_nodes.delete_at(0)

                stub_request(:post, graphql_url)
                  .with(body: hash_including("query" => a_string_including("openMergeRequests: ")))
                  .to_return(status: :ok, body: open_mrs.to_json)

                perform_request

                Rails.cache.delete(described_class.authored_mr_lists_cache_key(username))
                open_mr_nodes << opened_mr

                stub_request(:post, graphql_url)
                  .with(body: hash_including("query" => a_string_including("openMergeRequests: ")))
                  .to_return(status: :ok, body: open_mrs.to_json)

                expect(WebPush).not_to receive(:payload_send)

                perform_request
              end
            end

            context "and merge request has been merged in between" do
              let!(:subscriptions) { create_list(:web_push_subscription, 2, gitlab_user: user) }

              def payload_of_merged_mr_notification(mr)
                satisfy do |data|
                  message = JSON.parse(data[:message])
                  message["type"] == "push_notification" &&
                    message.dig(*%w[payload title]) == "A merge request was merged" &&
                    message.dig(*%w[payload options body]) == "#{mr["reference"]}: #{mr["titleHtml"]}" &&
                    message.dig(*%w[payload options data url]) == mr["webUrl"]
                end
              end

              it "sends web push notification" do
                perform_request

                Rails.cache.delete(described_class.authored_mr_lists_cache_key(username))

                open_mr_nodes = open_mrs.dig(*%w[data user openMergeRequests nodes])
                merged_mr_nodes = merged_mrs.dig(*%w[data user mergedMergeRequests nodes])
                merged_mr = open_mr_nodes.delete_at(0)
                merged_mr["mergedAt"] = Time.current
                merged_mr["mergeUser"] = {
                  "__typename" => "UserCore",
                  "username" => "rsarangadharan",
                  "avatarUrl" => "/uploads/-/system/user/avatar/21979359/avatar.png",
                  "webUrl" => "https://gitlab.com/rsarangadharan",
                  "lastActivityOn" => "2024-11-27",
                  "location" => "",
                  "status" => {"availability" => "NOT_SET", "message" => "Please @mention me so I see your message."}
                }
                merged_mr_nodes << merged_mr

                stub_request(:post, graphql_url)
                  .with(body: hash_including("query" => a_string_including("openMergeRequests: ")))
                  .to_return(status: :ok, body: open_mrs.to_json)
                stub_request(:post, graphql_url)
                  .with(body: hash_including("query" => a_string_including("mergedMergeRequests: ")))
                  .to_return(status: :ok, body: merged_mrs.to_json)

                expect(WebPush).to receive(:payload_send)
                  .with(payload_of_merged_mr_notification(merged_mr))
                  .exactly(subscriptions.count)

                perform_request
              end
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

          before do
            stub_request(:get, %r{^https://nominatim\.openstreetmap\.org/search\?addressdetails=1})
              .to_return(status: :not_found)
          end

          it "renders the actual template" do
            travel_to Time.utc(2024, 11, 20) do
              request
            end

            expect(response).to render_template("layouts/application")
            expect(response).to render_template("merge_requests/_user_merge_requests")

            expect(response.body).to include(%(<turbo-frame id="merge_requests_user_dto_#{username}">))
            # Project link
            expect(response.body).to include(%r{<a [^>]+href="https://gitlab.com/gitlab-org/gitlab">})
            expect(response.body).to include(%r{<a [^>]+href="https://gitlab.com/gitlab-org/security/gitlab-runner">})
            # Project avatar
            expect(response.body).to include(
              %r{<img [^>]+src="https://gitlab.com/uploads/-/system/project/avatar/278964/project_avatar.png"}
            )
            expect(response.body).to include(%(https://gitlab.com/uploads/-/system/project/avatar/250833/runner.png))
            # Issues
            expect(response.body).to include(%(>#32804</a>))
            ## Issue from security MR should be found in canonical repo
            expect(response.body).to include(%(href="https://gitlab.com/gitlab-org/gitlab-runner/-/issues/32804"))
            # MR links
            expect(response.body).to include(%(>!5166</a>))
            # Failed job link from downstream pipeline
            expect(response.body).to include(
              'href="https://gitlab.example.com/gitlab-org/analytics-section/product-analytics/product-analytics-devkit-mirror/-/jobs/8651198918">Failed<'
            )

            # Captions
            expect(response.body).to include(%r{10 merge requests, open for an average of\s+about 12 hours})
            expect(response.body).to include(%r{A total of\s+1311 merge requests})

            # Squash MR
            expect(response.body).to include(%(fa-solid fa-angles-down))
            # Unreviewed icon
            expect(response.body).to include(%(fa-solid fa-hourglass-start))
            # Reviewed icon
            expect(response.body).to include(%(fa-solid fa-check))
            # Old MRs
            expect(response.body).to include(%(text-danger))
          end

          it "renders the merged MRs from the last week" do
            travel_to Time.utc(2024, 11, 27) do
              request
            end

            expect(response.body).not_to include(%r{<a [^>]+href="https://gitlab.com/gitlab-org/gitlab-runner">})
            expect(response.body).not_to include(%(>#32804</a>))
          end
        end

        context "when turbo param is missing", :freeze_time do
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
