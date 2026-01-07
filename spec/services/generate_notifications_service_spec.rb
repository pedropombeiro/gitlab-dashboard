# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenerateNotificationsService, "#execute" do
  subject(:execute) { service.execute }

  let(:service) { described_class.new(user, type, fetch_service) }
  let(:user) { create(:gitlab_user, username: author) }
  let(:author) { "testuser" }
  let(:type) { :open }
  let(:fetch_service) { instance_double(FetchMergeRequestsService) }
  let(:response) { double("Response", errors: nil, next_scheduled_update_at: 5.minutes.from_now) }
  let(:dto) { instance_double(UserDto, errors: [], open_merge_requests: double(items: [])) }

  before do
    # Stub cache service to avoid actual caching in tests
    allow_any_instance_of(MergeRequestsCacheService).to receive(:write)
    allow_any_instance_of(MergeRequestsCacheService).to receive(:read).and_return(nil)

    allow(fetch_service).to receive(:parse_dto).and_return(dto)
  end

  context "when data is freshly fetched from GitLab" do
    let(:fetch_result) { FetchMergeRequestsService::FetchResult.new(response: response, freshly_fetched?: true) }

    before do
      allow(fetch_service).to receive(:execute).and_return(fetch_result)
    end

    it "broadcasts update to connected clients via Action Cable" do
      expect(MergeRequestBroadcaster).to receive(:broadcast_update).with(author, type, dto)

      execute
    end

    it "logs the broadcast action at info level" do
      allow(MergeRequestBroadcaster).to receive(:broadcast_update)
      expect(Rails.logger).to receive(:info)
        .with("[GenerateNotificationsService] Broadcasting update for #{author}/#{type} (fresh data)")
      execute
    end
  end

  context "when data is returned from cache" do
    let(:fetch_result) { FetchMergeRequestsService::FetchResult.new(response: response, freshly_fetched?: false) }

    before do
      allow(fetch_service).to receive(:execute).and_return(fetch_result)
    end

    it "does not broadcast to avoid duplicate updates" do
      expect(MergeRequestBroadcaster).not_to receive(:broadcast_update)

      execute
    end
  end
end
