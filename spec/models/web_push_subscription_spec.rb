require "rails_helper"

RSpec.describe WebPushSubscription, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:gitlab_user) }
  end

  describe "#publish" do
    let!(:user) { create(:gitlab_user) }
    let!(:subscription) { create(:web_push_subscription, gitlab_user: user) }

    let(:data) { {data: "test-data"} }

    subject(:publish) { subscription.publish(data) }

    before do
      allow(WebPush).to receive(:payload_send)

      Rails.application.credentials[:webpush] = {vapid_public_key: "pubkey", vapid_private_key: "privkey"}
    end

    it "calls WebPush with expected arguments" do
      expect(WebPush).to receive(:payload_send).with(
        message: data.to_json,
        ttl: 8.hours.in_seconds,
        endpoint: subscription.endpoint,
        p256dh: subscription.p256dh_key,
        auth: subscription.auth_key,
        vapid: {
          public_key: Rails.application.credentials.dig(:webpush, :vapid_public_key),
          private_key: Rails.application.credentials.dig(:webpush, :vapid_private_key)
        }
      )

      publish
    end

    it "updates notified_at", :freeze_time do
      expect { publish }.to change { subscription.notified_at }.to(Time.current)
    end

    it "does not update updated_at", :freeze_time do
      expect { publish }.not_to change { subscription.updated_at }
    end
  end
end
