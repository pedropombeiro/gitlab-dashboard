require "rails_helper"

RSpec.describe Admin::DashboardController, type: :controller do
  describe "GET /index" do
    def perform_request
      get :index
    end

    subject(:request) { perform_request }

    let!(:users) { create_list(:gitlab_user, 2) }

    it "returns http success" do
      request

      expect(response).to have_http_status :success
    end

    it "responds to html by default" do
      request

      expect(response.content_type).to eq "text/html; charset=utf-8"
    end

    context "with render_views" do
      render_views

      it "renders the actual template" do
        request

        expect(response).to render_template("layouts/application")
        expect(response).to render_template("admin/dashboard/index")

        users.each do |user|
          expect(response.body).to include(
            %(<a href="#{merge_requests_path(assignee: user.username)}">#{user.username}</a>)
          )
        end

        expect(response.body).not_to include(%(<caption class="caption-top">Web Push Subscriptions</caption>))
      end

      context "with subscription" do
        let!(:subscription) do
          create(:web_push_subscription, gitlab_user: users.first, created_at: 1.day.ago, notified_at: 10.seconds.ago)
        end

        it "renders the actual template" do
          request

          expect(response).to render_template("layouts/application")
          expect(response).to render_template("admin/dashboard/index")

          users.each do |user|
            expect(response.body).to include(
              %(<a href="#{merge_requests_path(assignee: user.username)}">#{user.username}</a>)
            )
          end

          expect(response.body).to include(%(<caption class="caption-top">Web Push Subscriptions</caption>))
          expect(response.body).to include(%(<time datetime="#{subscription.created_at.iso8601}"))
          expect(response.body).to include(%(<time datetime="#{subscription.notified_at.iso8601}"))
        end
      end
    end
  end
end
