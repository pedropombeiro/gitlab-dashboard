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

    around do |example|
      travel_to Time.utc(2024, 11, 20) do
        example.run
      end
    end

    pending "todo"
  end
end
