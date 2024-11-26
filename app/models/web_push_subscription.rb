class WebPushSubscription < ApplicationRecord
  encrypts :auth_key, :p256dh_key

  belongs_to :gitlab_user

  def publish(data)
    WebPush.payload_send(
      message: data.to_json,
      ttl: 8.hours.in_seconds,
      endpoint: endpoint,
      p256dh: p256dh_key,
      auth: auth_key,
      vapid: {
        public_key: Rails.application.credentials.dig(:webpush, :vapid_public_key),
        private_key: Rails.application.credentials.dig(:webpush, :vapid_private_key)
      }
    )

    update_column(:notified_at, Time.current)
  end
end
