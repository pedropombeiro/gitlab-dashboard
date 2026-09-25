# frozen_string_literal: true

require "rails_helper"

RSpec.describe GenerateNotificationsService, "#execute" do
  include ActiveSupport::Testing::TimeHelpers

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

  context "when sending a notification" do
    let(:fetch_result) { FetchMergeRequestsService::FetchResult.new(response: response, freshly_fetched?: true) }
    let(:failed_job) { double(allowFailure: false) }
    let(:merge_request) { double(headPipeline: double(failedJobs: double(nodes: [failed_job]))) }
    let(:previous_dto) { instance_double(UserDto, open_merge_requests: double(items: [])) }
    let(:dto) { instance_double(UserDto, errors: [], open_merge_requests: double(items: [merge_request])) }
    before { create(:web_push_subscription, gitlab_user: user) }

    before do
      allow(fetch_service).to receive(:execute).and_return(fetch_result)
      allow(fetch_service).to receive(:parse_dto).and_return(previous_dto, dto)
      allow(MergeRequestBroadcaster).to receive(:broadcast_update)
      notification = {title: "Pipeline failed", body: "A blocking job failed"}
      allow(ComputeMergeRequestChangesService).to receive(:new)
        .and_return(instance_double(ComputeMergeRequestChangesService, execute: [notification]))
    end

    it "includes the attention-needed count" do
      expect_any_instance_of(WebPushSubscription).to receive(:publish)
        .with(hash_including(type: "push_notification", payload: hash_including(appBadgeCount: 1)))

      execute
    end

    context "when fetching merged merge requests" do
      let(:type) { :merged }
      let(:previous_dto) { instance_double(UserDto) }
      let(:dto) { instance_double(UserDto, errors: []) }
      let(:open_response) { double("OpenResponse", errors: nil) }
      let(:open_dto) { instance_double(UserDto, errors: [], open_merge_requests: double(items: [merge_request])) }

      before do
        allow_any_instance_of(MergeRequestsCacheService).to receive(:read) do |_instance, _author, read_type|
          open_response if read_type == :open
        end
        allow(fetch_service).to receive(:parse_dto) do |source, parse_type|
          if parse_type == :open
            open_dto
          elsif source.nil?
            previous_dto
          else
            dto
          end
        end
      end

      it "includes the attention-needed count from the cached open merge requests" do
        expect_any_instance_of(WebPushSubscription).to receive(:publish)
          .with(hash_including(type: "push_notification", payload: hash_including(appBadgeCount: 1)))

        execute
      end

      context "without cached open merge requests" do
        let(:open_response) { nil }

        it "sends the notification without an app badge count" do
          expect_any_instance_of(WebPushSubscription).to receive(:publish)
            .with(hash_including(type: "push_notification", payload: hash_excluding(:appBadgeCount)))

          execute
        end
      end
    end

    context "when a merge request was merged" do
      let(:type) { :merged }
      let(:merged_at) { Time.zone.local(2026, 8, 31, 23, 30) }
      let(:merged_mr) { double(iid: "42", mergedAt: merged_at) }
      let(:other_mr) { double(iid: "7", mergedAt: Time.zone.local(2026, 7, 10)) }
      let(:previous_dto) { instance_double(UserDto) }
      let(:dto) { instance_double(UserDto, errors: [], merged_merge_requests: double(items: [merged_mr, other_mr])) }
      let(:notification) { {type: :merge_request_merged, title: "Merged", body: "!42", tag: "42"} }

      before do
        allow(fetch_service).to receive(:parse_dto).and_return(previous_dto, dto)
        allow(ComputeMergeRequestChangesService).to receive(:new)
          .and_return(instance_double(ComputeMergeRequestChangesService, execute: [notification]))
        allow_any_instance_of(WebPushSubscription).to receive(:publish)
        allow(Rails.cache).to receive(:delete).and_call_original
      end

      def stats_cache_key(month)
        described_class.monthly_merged_mr_stats_cache_key(author, month)
      end

      around { |example| travel_to(Time.zone.local(2026, 9, 25)) { example.run } }

      it "clears only the cached stats for the month the merge request was merged in" do
        execute

        expect(Rails.cache).to have_received(:delete).with(stats_cache_key(Date.new(2026, 8, 1)))
        expect(Rails.cache).not_to have_received(:delete).with(stats_cache_key(Date.new(2026, 9, 1)))
        expect(Rails.cache).not_to have_received(:delete).with(stats_cache_key(Date.new(2026, 7, 1)))
      end

      context "when the merge timestamp is missing" do
        let(:merged_at) { nil }

        it "clears the current month's cached stats" do
          execute

          expect(Rails.cache).to have_received(:delete).with(stats_cache_key(Date.new(2026, 9, 1)))
        end
      end
    end

    context "without notification changes" do
      let(:type) { :merged }

      before do
        allow(ComputeMergeRequestChangesService).to receive(:new)
          .and_return(instance_double(ComputeMergeRequestChangesService, execute: []))
      end

      it "does not read open merge requests for the badge count" do
        expect_any_instance_of(MergeRequestsCacheService).not_to receive(:read).with(author, :open)

        execute
      end
    end
  end
end
