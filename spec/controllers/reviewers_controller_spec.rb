require "rails_helper"
require "erb"
require_relative "../support/graphql_shared_contexts"

RSpec.describe ReviewersController, type: :controller do
  include ActiveSupport::Testing::TimeHelpers

  include_context "stub graphql client"

  describe "GET /index" do
    def perform_request
      get :index, params: params
    end

    let(:group_path) { "gitlab-org/maintainers/cicd-verify" }
    let(:params) { {group_path: group_path}.compact }

    subject(:request) { perform_request }

    it "responds to html by default" do
      request

      expect(response.content_type).to eq "text/html; charset=utf-8"
    end

    context "with render_views" do
      render_views

      it "renders the actual template" do
        request

        expect(response).to have_http_status(:ok)
        expect(response).to render_template("layouts/application")

        # Includes turbo frame with reviewers list
        expect(response.body).to include(
          %(src="#{ERB::Util.html_escape(reviewers_list_path(group_path: group_path))}")
        )
      end

      context "when group_path is not specified" do
        let(:params) { nil }

        it "redirects to gitlab-org/maintainers/cicd-verify" do
          request

          expect(response).to redirect_to action: :index, group_path: group_path
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

    # Just after the lastActivityOn values in the fixture, so that the activity
    # and scoring paths in the DTO see realistic timestamps.
    around do |example|
      travel_to Time.utc(2025, 1, 22, 12) do
        example.run
      end
    end

    let_it_be(:group_reviewers_response_body) { YAML.load_file(file_fixture("group_reviewers.yml")) }

    let(:group_path) { "gitlab-org" }
    let(:params) { {group_path: group_path} }

    let!(:group_reviewers_request_stub) do
      stub_request(:post, graphql_url)
        .with(body: hash_including(
          "operationName" => "GitlabClient__GroupReviewersQuery",
          "variables" => hash_including("fullPath" => group_path)
        ))
        .to_return_json(body: group_reviewers_response_body["verify"])
    end

    context "when the group is not found" do
      let!(:group_reviewers_request_stub) do
        stub_request(:post, graphql_url)
          .with(body: hash_including("operationName" => "GitlabClient__GroupReviewersQuery"))
          .to_return_json(body: {data: {group: nil}})
      end

      it "returns http not_found" do
        request

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when the group is known" do
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
          2.times { perform_request }

          expect(group_reviewers_request_stub).to have_been_requested.twice
        end

        context "with cache enabled", :with_cache do
          it "only calls api once" do
            2.times { perform_request }

            expect(response).to have_http_status :success
            expect(group_reviewers_request_stub).to have_been_requested.once
          end
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

          expect(response).to have_http_status(:ok)
          expect(response).to render_template("reviewers/_reviewers")

          expect(response.body).to include(
            %(<turbo-frame id="reviewers_group_reviewers_dto_#{group_path}">)
          )

          # Human reviewers are listed, bots are filtered out
          expect(response.body).to include("rkadam3")
          expect(response.body).not_to include("gitlab-infra-mgmt-bot")
          expect(response.body).not_to include("employment-bot")

          # Active review counts link to the reviewer's dashboard, excluding
          # merge requests they already approved
          expect(response.body).to include(
            ERB::Util.html_escape("not[approved_by_usernames][]=rkadam3")
          )

          # Review counts are colour-coded against each reviewer's limit
          expect(response.body).to match(/text-(success|warning|danger)/)
        end

        context "in development, where the score column is shown" do
          before do
            allow(Rails.env).to receive(:development?).and_return(true)
          end

          it "renders the score in a closed cell" do
            request

            expect(response).to have_http_status(:ok)
            expect(response.body).to include(%(<th scope="col" class="text-end">Score</th>))
            expect(response.body).to match(
              %r{<td class="text-end text-secondary">\s*<span>\[\d+, \d+\]</span>\s*</td>}
            )

            # Every row must close each cell it opens.
            rows = response.body.scan(%r{<tr[^>]*>.*?</tr>}m)
            expect(rows).not_to be_empty
            rows.each do |row|
              expect(row.scan("<td").size).to eq(row.scan("</td>").size)
            end
          end
        end
      end
    end
  end
end
