require "rails_helper"

RSpec.describe Api::WebPushSubscriptionsController, type: :controller do
  describe "POST /create" do
    let(:user) { create(:gitlab_user) }

    before do
      session[:user_id] = user.username
    end

    it "returns http success" do
      expect do
        post :create, params: {endpoint: "endpoint", keys: {auth: "auth", p256dh: "p256dh"}}
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
end
