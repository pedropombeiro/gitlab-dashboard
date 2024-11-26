FactoryBot.define do
  factory :web_push_subscription do
    gitlab_user
    endpoint { "endpoint" }
    auth_key { "authkey" }
    p256dh_key { "p256dh_key" }
    user_agent { "user_agent" }
    created_at { "2024-11-26 22:06:23" }
    updated_at { "2024-11-26 22:06:23" }
    notified_at { "2024-11-26 22:06:23" }
  end
end
