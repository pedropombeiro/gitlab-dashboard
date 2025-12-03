require "rails_helper"
require "erb"
require_relative "../support/graphql_shared_contexts"

RSpec.describe MergeRequestsController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  include_context "stub graphql client"

  shared_context "a request updating current_user" do
    it "returns http success and creates user with correct timestamp" do
      expect(GitlabUser.find_by_username(author)).to be_nil

      request

      expect(response).to have_http_status :success
      expect(GitlabUser.find_by_username(author)).to have_attributes(
        created_at: Time.current,
        updated_at: Time.current,
        contacted_at: Time.current
      )
    end

    context "with referrer" do
      let(:params) { {author: author, referrer: merge_requests_path(author: "user.2")} }

      it "returns http success and does not create user" do
        expect { request }.not_to change { GitlabUser.find_by_username(author) }.from(nil)
      end

      context "with render_views" do
        include ActionView::Helpers::SanitizeHelper

        before do
          stub_request(:get, %r{^https://nominatim\.openstreetmap\.org/search\?addressdetails=1})
            .to_return(status: :not_found)
        end

        render_views

        it "renders the actual template" do
          request

          expect(response).to have_http_status(:ok)

          # Includes header with link to user's merge requests
          response.body.scan(%r{<turbo-frame .*src=.*>}).each do |match|
            expect(match).to include(sanitize(params.to_query))
          end
        end
      end
    end
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
            "operationName" => "GitlabClient__UserQuery",
            "variables" => {username: "non-existent"}
          ))
          .to_return_json(body: {data: {user: nil}})
      end

      let(:params) { {author: "non-existent"} }

      it "returns http not_found" do
        request

        expect(response).to have_http_status(:not_found)
        expect(GitlabUser.find_by_username("non-existent")).to be_nil
      end
    end

    context "when user is known" do
      let(:author) { "user.1" }
      let(:params) { {author: author} }
      let(:user_response_body) do
        {
          data: {
            user: {
              username: author,
              avatarUrl: "/images/avatar.png",
              webUrl: "https://gitlab.example.com/#{author}"
            }
          }
        }
      end

      let!(:user_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__UserQuery",
            "variables" => {username: author}
          ))
          .to_return_json(status: :ok, body: user_response_body)
      end

      context "with time frozen", :freeze_time do
        it_behaves_like "a request updating current_user"
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
          expect(response).to render_template("shared/_user_image")

          # Includes header with link to user's merge requests
          expect(response.body).to include(
            %(<a href="javascript:void(0);" role="button" data-clipboard-target="source" class="fw-normal">#{author}</a>)
          )
          expect(response.body).to include(
            %(<a target="_blank" rel="noopener" href="https://gitlab.example.com/#{author}"><span class="h4 me-1" data-clipboard-target="source">#{author}</span><i ).gsub('"', "&quot;")
          )
          # and user's avatar
          expect(response.body).to include(
            %(<img class="rounded float-left" src="https://gitlab.example.com/images/avatar.png" width="24" height="24" />)
          )
          # Includes turbo frame with merge requests lists
          expect(response.body).to include(
            %(src="#{ERB::Util.html_escape(open_merge_requests_list_path(author: author))}")
          )
          expect(response.body).to include(
            %(src="#{ERB::Util.html_escape(merged_merge_requests_list_path(author: author))}")
          )
        end
      end

      context "when author is not specified" do
        let(:params) { nil }

        it "returns network_authentication_required" do
          request

          expect(response).to have_http_status(:network_authentication_required)
          expect(GitlabUser.find_by_username(author)).to be_nil
        end

        context "when GITLAB_TOKEN is specified" do
          context "and session does not contain user_id" do
            before do
              allow(Rails.application.credentials).to receive(:gitlab_token).and_return("secret-token")
            end

            let!(:user_request_stub) do
              stub_request(:post, graphql_url)
                .with(body: hash_including(
                  "operationName" => "GitlabClient__CurrentUserQuery",
                  "variables" => {}
                ))
                .to_return_json(body: user_response_body)
            end

            it "redirects to author specified in GITLAB_TOKEN" do
              request

              expect(response).to redirect_to action: :index, author: author
              expect(GitlabUser.find_by_username(author)).to be_nil
            end
          end

          context "when session contains user_id" do
            before do
              session[:user_id] = "user.1"
            end

            it "redirects to author specified in user_id" do
              expect(Rails.application.credentials).not_to receive(:gitlab_token)

              request

              expect(response).to redirect_to action: :index, author: "user.1"
              expect(GitlabUser.find_by_username(author)).to be_nil
            end
          end
        end
      end

      context "with legacy assignee query param" do
        let(:params) { {assignee: author} }

        it "redirects to author specified in assignee" do
          request

          expect(response).to redirect_to action: :index, author: author
          expect(GitlabUser.find_by_username(author)).to be_nil
        end

        context "with invalid assignee containing special characters" do
          let(:params) { {assignee: "user<script>alert('xss')</script>"} }

          it "renders 404 for invalid username format" do
            request

            expect(response).to have_http_status(:not_found)
          end
        end

        context "with invalid assignee containing SQL injection attempt" do
          let(:params) { {assignee: "user'; DROP TABLE users--"} }

          it "renders 404 for invalid username format" do
            request

            expect(response).to have_http_status(:not_found)
          end
        end

        context "with invalid assignee that is too long" do
          let(:params) { {assignee: "a" * 256} }

          it "renders 404 for username exceeding length limit" do
            request

            expect(response).to have_http_status(:not_found)
          end
        end
      end
    end
  end

  describe "GET /open_list" do
    def perform_request
      get :open_list, params: params, format: format
    end

    subject(:request) { perform_request }

    let(:format) { nil }

    around do |example|
      travel_to Time.utc(2024, 11, 20) do
        example.run
      end
    end

    context "when author is unknown" do
      before do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__UserQuery",
            "variables" => {username: "non-existent"}
          ))
          .to_return_json(body: {data: {user: nil}})
      end

      let(:params) { {author: "non-existent"} }

      it "returns http not_found" do
        request

        expect(response).to have_http_status(:not_found)
        expect(GitlabUser.find_by_username("non-existent")).to be_nil
      end
    end

    context "when author is known" do
      let_it_be(:issues) { YAML.load_file(file_fixture("issues.yml")) }

      let!(:reviewer_responses) { YAML.load_file(file_fixture("reviewers.yml")) }
      let(:open_mrs) { YAML.load_file(file_fixture("open_merge_requests.yml"))["one"] }
      let(:author) { "pedropombeiro" }
      let(:params) { {author: author} }

      let!(:user_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__UserQuery",
            "variables" => {username: author}
          ))
          .to_return_json(body: {data: {user: {username: author, avatarUrl: "", webUrl: ""}}})
      end

      let!(:open_mrs_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__OpenMergeRequestsQuery",
            "variables" => hash_including(
              "author" => author,
              "updatedAfter" => an_instance_of(String)
            )
          ))
          .to_return_json(body: open_mrs)
      end

      let!(:reviewers_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__ReviewerQuery",
            "variables" => hash_including(
              "reviewer" => an_instance_of(String),
              "activeReviewsAfter" => an_instance_of(String)
            )
          ))
          .to_return do |request|
            username = JSON.parse(request.body).dig(*%w[variables reviewer])

            {body: reviewer_responses.fetch(username).to_json}
          end
      end

      let!(:issues_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__ProjectIssuesQuery",
            "variables" => hash_including(
              "projectFullPath" => "gitlab-org/gitlab",
              "issueIids" => an_array_matching(%w[503315 446287 506226 481411 506385 502403 472974])
            )
          ))
          .to_return_json(body: issues["project_0"])
      end

      let!(:project_version_request_stub) do
        stub_request(:get, "https://gitlab.com/gitlab-org/gitlab/-/raw/master/VERSION").to_return(body: "17.8.0-pre\n")
      end

      it_behaves_like "a request updating current_user"

      context "when user exists" do
        let!(:user) { create(:gitlab_user, username: author, contacted_at: 1.day.ago) }

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
            expect(issues_request_stub).to have_been_requested.twice
          end

          context "with cache enabled", :with_cache do
            it "only calls api once" do
              # A second request is served from the cache, and doesn't generate more API calls
              2.times { perform_request }

              expect(response).to have_http_status :success

              expect(open_mrs_request_stub).to have_been_requested.once
              expect(issues_request_stub).to have_been_requested.once
            end

            context "and merge request has been opened in between" do
              let!(:subscription) { create(:web_push_subscription, gitlab_user: user) }

              it "does not send web push notification" do
                open_mr_nodes = open_mrs.dig(*%w[data user openMergeRequests nodes])
                opened_mr = open_mr_nodes.delete_at(0)

                stub_request(:post, graphql_url)
                  .with(body: hash_including("operationName" => "GitlabClient__OpenMergeRequestsQuery"))
                  .to_return_json(body: open_mrs)

                perform_request

                Rails.cache.delete(described_class.authored_mr_lists_cache_key(author, :open))
                open_mr_nodes << opened_mr

                stub_request(:post, graphql_url)
                  .with(body: hash_including("operationName" => "GitlabClient__OpenMergeRequestsQuery"))
                  .to_return_json(body: open_mrs)

                expect(WebPush).not_to receive(:payload_send)

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
            request

            expect(response).to render_template("layouts/application")
            expect(response).to render_template("merge_requests/_open_merge_requests")

            expect(response.body).to include(%(<turbo-frame id="open_merge_requests_user_dto_#{author}">))
            # Project link
            expect(response.body).to include(%r{<a [^>]+href="https://gitlab.com/gitlab-org/gitlab">})
            # Project avatar
            expect(response.body).to include(
              %r{<img [^>]+src="https://gitlab.com/uploads/-/system/project/avatar/278964/project_avatar.png"}
            )
            expect(response.body).to include(%(https://gitlab.com/uploads/-/system/project/avatar/278964/project_avatar.png))
            # Issues
            expect(response.body).to include(%r{>\s*#506226.*<img }m)
            # MR links
            expect(response.body).to include(%(>!173916</a>))
            # Failed job link from downstream pipeline
            expect(response.body).to include(
              'href="https://gitlab.example.com/gitlab-org/analytics-section/product-analytics/product-analytics-devkit-mirror/-/jobs/8651198918">Failed<'
            )

            # Captions
            expect(response.body).to include(%r{10 merge requests,\s+open\s+for\s+an\s+average\s+of\s+<span>\s+about 12 hours})

            # Squash MR
            expect(response.body).to include(%(bi bi-chevron-bar-down))
            # Unreviewed icon
            expect(response.body).to include(%(fa-solid fa-hourglass-start))
            # Reviewed icon
            expect(response.body).to include(%(fa-solid fa-check))
            # Old MRs
            expect(response.body).to include(%(text-danger))

            # Blocked MRs
            expect(response.body).to include(%(This MR is blocked by 1 merge request: !173886))
          end
        end

        private

        def create_merged_mrs_request_stub
          stub_request(:post, graphql_url)
            .with(body: hash_including(
              "operationName" => "GitlabClient__MergedMergeRequestsQuery",
              "variables" => {
                "author" => author,
                "mergedAfter" => 1.week.ago
              }
            ))
            .to_return_json(body: merged_mrs)
        end
      end
    end
  end

  describe "GET /merged_list" do
    def perform_request
      get :merged_list, params: params, format: format
    end

    subject(:request) { perform_request }

    let(:format) { nil }
    let(:params) { {author: author} }

    around do |example|
      travel_to Time.utc(2024, 11, 20) do
        example.run
      end
    end

    context "when author is unknown" do
      before do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__UserQuery",
            "variables" => {username: "non-existent"}
          ))
          .to_return_json(body: {data: {user: nil}})
      end

      let(:author) { "non-existent" }

      it "returns http not_found" do
        request

        expect(response).to have_http_status(:not_found)
        expect(GitlabUser.find_by_username("non-existent")).to be_nil
      end
    end

    context "when author is known" do
      let_it_be(:issues) { YAML.load_file(file_fixture("issues.yml")) }

      let!(:reviewer_responses) { YAML.load_file(file_fixture("reviewers.yml")) }
      let(:merged_mrs) { YAML.load_file(file_fixture("merged_merge_requests.yml"))["one"] }
      let(:author) { "pedropombeiro" }

      let!(:user_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__UserQuery",
            "variables" => {username: author}
          ))
          .to_return_json(body: {data: {user: {username: author, avatarUrl: "", webUrl: ""}}})
      end

      let!(:reviewers_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__ReviewerQuery",
            "variables" => hash_including(
              "reviewer" => an_instance_of(String),
              "activeReviewsAfter" => an_instance_of(String)
            )
          ))
          .to_return do |request|
          username = JSON.parse(request.body).dig(*%w[variables reviewer])

          {body: reviewer_responses.fetch(username).to_json}
        end
      end

      let!(:merged_mrs_request_stub) { create_merged_mrs_request_stub }
      let!(:issues_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__ProjectIssuesQuery",
            "variables" => hash_including(
              "projectFullPath" => "gitlab-org/gitlab",
              "issueIids" => including(
                "506404", "505703", "457221", "505810", "503748", "472974", "442395", "500447", "502934", "502431",
                "497562", "354756"
              )
            )
          ))
          .to_return_json(body: issues["project_0"])
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__ProjectIssuesQuery",
            "variables" => hash_including(
              "projectFullPath" => "gitlab-org/security/gitlab-runner",
              "issueIids" => %w[32804]
            )
          ))
          .to_return_json(body: issues["project_1"])
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__ProjectIssuesQuery",
            "variables" => hash_including(
              "projectFullPath" => "gitlab-org/gitlab-runner",
              "issueIids" => %w[32804]
            )
          ))
          .to_return_json(body: issues["project_2"])
      end

      it "returns http success" do
        request

        expect(response).to have_http_status :success
      end

      it_behaves_like "a request updating current_user"

      context "when user exists" do
        let!(:user) { create(:gitlab_user, username: author, contacted_at: 1.day.ago) }

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

            expect(merged_mrs_request_stub).to have_been_requested.twice
            expect(issues_request_stub).to have_been_requested.twice
          end

          context "with cache enabled", :with_cache do
            let(:open_mrs) { YAML.load_file(file_fixture("open_merge_requests.yml"))["one"] }
            let!(:open_mrs_request_stub) do
              stub_request(:post, graphql_url)
                .with(body: hash_including(
                  "operationName" => "GitlabClient__OpenMergeRequestsQuery",
                  "variables" => hash_including(
                    "author" => author,
                    "updatedAfter" => an_instance_of(String)
                  )
                ))
                .to_return_json(body: open_mrs)
            end

            it "only calls api once" do
              # A second request is served from the cache, and doesn't generate more API calls
              2.times { perform_request }

              expect(response).to have_http_status :success

              expect(merged_mrs_request_stub).to have_been_requested.once
              expect(issues_request_stub).to have_been_requested.once
            end

            context "and merge request has been opened in between" do
              let!(:subscription) { create(:web_push_subscription, gitlab_user: user) }

              it "does not send web push notification" do
                open_mr_nodes = open_mrs.dig(*%w[data user openMergeRequests nodes])
                opened_mr = open_mr_nodes.delete_at(0)

                stub_request(:post, graphql_url)
                  .with(body: hash_including("operationName" => "GitlabClient__OpenMergeRequestsQuery"))
                  .to_return_json(body: open_mrs)

                perform_request

                Rails.cache.delete(described_class.authored_mr_lists_cache_key(author, :open))
                open_mr_nodes << opened_mr

                stub_request(:post, graphql_url)
                  .with(body: hash_including("operationName" => "GitlabClient__OpenMergeRequestsQuery"))
                  .to_return_json(body: open_mrs)

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

                Rails.cache.delete(described_class.authored_mr_lists_cache_key(author, :merged))

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
                  .with(body: hash_including("operationName" => "GitlabClient__OpenMergeRequestsQuery"))
                  .to_return_json(body: open_mrs)
                stub_request(:post, graphql_url)
                  .with(body: hash_including("operationName" => "GitlabClient__MergedMergeRequestsQuery"))
                  .to_return_json(body: merged_mrs)

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
            request

            expect(response).to render_template("layouts/application")
            expect(response).to render_template("merge_requests/_merged_merge_requests")

            expect(response.body).to include(%(<turbo-frame id="merged_merge_requests_user_dto_#{author}">))
            # Project link
            expect(response.body).to include(%r{<a [^>]+href="https://gitlab.com/gitlab-org/gitlab">})
            expect(response.body).to include(%r{<a [^>]+href="https://gitlab.com/gitlab-org/security/gitlab-runner">})
            # Project avatar
            expect(response.body).to include(
              %r{<img [^>]+src="https://gitlab.com/uploads/-/system/project/avatar/278964/project_avatar.png"}
            )
            expect(response.body).to include(%(https://gitlab.com/uploads/-/system/project/avatar/250833/runner.png))
            # Issues
            expect(response.body).to include(
              %r{<span class="d-inline-flex align-items-center badge rounded-pill text-white" style="background-color: #339AF0 !important;">.*#505810.*<img}m
            )
            expect(response.body).to include(
              %r{<span class="d-inline-flex align-items-center badge rounded-pill text-black" style="background-color: #FCC419 !important;">.*#32804.*<img}m
            )
            ## Issue from security MR should be found in canonical repo
            expect(response.body).to include(%(href="https://gitlab.com/gitlab-org/gitlab-runner/-/issues/32804"))
            # MR links
            expect(response.body).to include(%(>!5166</a>))

            # Captions
            expect(response.body).to include(%r{A total of\s+1,311 merge requests})
          end
        end
      end

      private

      def create_merged_mrs_request_stub
        stub_request(:post, graphql_url)
          .with(body: hash_including(
            "operationName" => "GitlabClient__MergedMergeRequestsQuery",
            "variables" => {
              "author" => author,
              "mergedAfter" => 1.week.ago
            }
          ))
          .to_return_json(body: merged_mrs)
      end
    end
  end
end
