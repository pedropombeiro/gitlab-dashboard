FactoryBot.define do
  factory :web_push_subscription do
    gitlab_user
    endpoint { "endpoint" }
    auth_key { "authkey" }
    p256dh_key { "p256dh_key" }
    user_agent { "user_agent" }
    created_at { 10.days.ago }
    updated_at { 9.days.ago }
    notified_at { 30.minutes.ago }
  end
end
