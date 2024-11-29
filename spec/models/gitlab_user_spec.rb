require "rails_helper"

RSpec.describe GitlabUser, type: :model do
  describe "associations" do
    it { is_expected.to have_many(:web_push_subscriptions) }
  end
end
