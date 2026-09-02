require "rails_helper"

RSpec.describe ScheduleSubscribedUsersCacheRefreshJob do
  subject(:perform) { described_class.perform_now }

  let!(:subscribed_user) { create(:gitlab_user, contacted_at: 2.days.ago) }
  let!(:active_subscribed_user) { create(:gitlab_user, contacted_at: 1.minute.ago) }
  let(:cache_service) { instance_double(MergeRequestsCacheService) }

  before do
    create(:web_push_subscription, gitlab_user: subscribed_user)
    create(:web_push_subscription, gitlab_user: active_subscribed_user)
    allow(MergeRequestsCacheService).to receive(:new).and_return(cache_service)
    allow(cache_service).to receive(:needs_scheduled_update?).and_return(false)
  end

  it "checks subscribed users even when they are not recently active" do
    perform

    expect(cache_service).to have_received(:needs_scheduled_update?).with(subscribed_user.username, :open)
    expect(cache_service).to have_received(:needs_scheduled_update?).with(subscribed_user.username, :merged)
    expect(cache_service).not_to have_received(:needs_scheduled_update?).with(active_subscribed_user.username, anything)
  end

  it "enqueues stale lists" do
    allow(cache_service).to receive(:needs_scheduled_update?).with(subscribed_user.username, :open).and_return(true)
    allow(MergeRequestsFetchJob).to receive(:perform_later)

    perform

    expect(MergeRequestsFetchJob).to have_received(:perform_later).with(subscribed_user.username, :open)
  end
end
