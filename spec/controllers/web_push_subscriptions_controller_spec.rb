require "rails_helper"

RSpec.describe Api::WebPushSubscriptionsController, type: :controller do
  describe "POST /create" do
    let(:user) { create(:gitlab_user) }
    let(:valid_params) { {endpoint: "endpoint", keys: {auth: "auth", p256dh: "p256dh"}} }

    before do
      session[:user_id] = user.username
    end

    context "with valid CSRF token and origin" do
      before do
        request.headers["HTTP_ORIGIN"] = "http://test.host"
      end

      it "creates a web push subscription" do
        expect do
          post :create, params: valid_params
        end.to change { WebPushSubscription.find_by_gitlab_user_id(user.id) }.to(an_instance_of(WebPushSubscription))

        expect(response).to have_http_status(:ok)
        expect(WebPushSubscription.find_by_gitlab_user_id(user.id)).to have_attributes(
          gitlab_user_id: user.id,
          endpoint: "endpoint",
          auth_key: "auth",
          p256dh_key: "p256dh"
        )
      end
    end

    context "without user session" do
      before do
        session[:user_id] = nil
      end

      it "returns unauthorized" do
        post :create, params: valid_params

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with invalid origin" do
      before do
        request.headers["HTTP_ORIGIN"] = "https://malicious-site.com"
      end

      it "returns forbidden" do
        post :create, params: valid_params

        expect(response).to have_http_status(:forbidden)
      end
    end

    context "without origin header" do
      it "allows the request" do
        expect do
          post :create, params: valid_params
        end.to change { WebPushSubscription.count }.by(1)

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
