FactoryBot.define do
  factory :gitlab_user do
    sequence(:username) { |n| "User #{n}" }
    created_at { "2024-11-26 22:06:06" }
    updated_at { "2024-11-26 22:06:06" }
    contacted_at { "2024-11-26 22:06:06" }
  end
end
