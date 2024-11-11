# frozen_string_literal: true

module WebPushConcern
  extend ActiveSupport::Concern

  def web_push(message, subscription)
    WebPush.payload_send(
      message: message,
      endpoint: subscription["endpoint"],
      p256dh: subscription["keys"]["p256dh"],
      auth: subscription["keys"]["auth"],
      vapid: {
        subject: "mailto:gitlab-dashboard@pedro.pombei.ro",
        public_key: Rails.application.credentials.dig(:webpush, :vapid_public_key),
        private_key: Rails.application.credentials.dig(:webpush, :vapid_private_key)
      }
    )
  end
end
