require "rails_helper"

RSpec.describe MergeRequestsFetchJob, :with_cache, :freeze_time do
  let(:user) { create(:gitlab_user) }
  let(:other_user) { create(:gitlab_user) }
  let(:graphql_url) { "#{GitlabClient.gitlab_instance_url}/api/graphql" }
  let(:cache_service) { MergeRequestsCacheService.new }

  it "defers background refreshes after a wrapped 429 and resumes on the recurring schedule" do
    previous_response = OpenStruct.new(updated_at: 10.minutes.ago, next_scheduled_update_at: 5.minutes.ago)
    cache_service.write(user.username, :open, previous_response)
    rejected = stub_request(:post, graphql_url).to_return(status: 429, headers: {"Retry-After" => "120"})
    allow(described_class).to receive(:perform_later)
    allow(MergeRequestBroadcaster).to receive(:broadcast_update)

    described_class.perform_now(user.username, :open)
    expect(rejected).to have_been_requested.once
    expect(cache_service.read(user.username, :open)).to eq(previous_response)

    travel 119.seconds
    described_class.perform_now(other_user.username, :merged)
    ScheduleCacheRefreshJob.perform_now
    expect(rejected).to have_been_requested.once
    expect(described_class).not_to have_received(:perform_later)
    expect(MergeRequestBroadcaster).not_to have_received(:broadcast_update)
    expect(cache_service.read(user.username, :open)).to eq(previous_response)

    travel 1.second
    ScheduleCacheRefreshJob.perform_now
    expect(described_class).to have_received(:perform_later).with(user.username, :open)

    stub_request(:post, graphql_url)
      .with(body: hash_including("operationName" => "GitlabClient__OpenMergeRequestsQuery"))
      .to_return_json(body: {data: {user: {openMergeRequests: {nodes: []}}}})

    described_class.perform_now(user.username, :open)
    expect(a_request(:post, graphql_url)).to have_been_made.twice
    expect(cache_service.read(user.username, :open).updated_at).to eq(Time.current)
    expect(MergeRequestBroadcaster).to have_received(:broadcast_update).with(user.username, :open, instance_of(UserDto))
  end
end
