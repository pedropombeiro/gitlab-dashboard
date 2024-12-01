FactoryBot.define do
  factory :gitlab_user do
    sequence(:username) { |n| "User #{n}" }
    created_at { 1.month.ago }
    updated_at { 3.weeks.ago }
    contacted_at { 5.minutes.ago }
  end
end
