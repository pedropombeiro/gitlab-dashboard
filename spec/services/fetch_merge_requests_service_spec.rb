# frozen_string_literal: true

require "rails_helper"

RSpec.describe FetchMergeRequestsService do
  describe "#enrich_open_merge_requests" do
    let(:service) { described_class.new("author") }
    let(:stages) { %i[fill_reviewers_info fill_project_milestone fill_linked_work_items fill_approval_state] }
    let(:requests_per_stage) { described_class::MAX_CONCURRENT_REQUESTS }

    it "runs every stage while capping in-flight requests across all stages" do
      running = 0
      peak = 0
      completed = 0

      stages.each do |stage|
        allow(service).to receive(stage) do
          Sync do
            requests_per_stage.times.map do
              service.send(:request_limiter).async do
                running += 1
                peak = [peak, running].max
                sleep 0.001
                completed += 1
              ensure
                running -= 1
              end
            end.map(&:wait)
          end
        end
      end

      service.send(:enrich_open_merge_requests, [])

      expect(completed).to eq(stages.size * requests_per_stage)
      expect(peak).to eq(described_class::MAX_CONCURRENT_REQUESTS)
    end
  end

  describe "FetchResult" do
    subject(:result) { described_class::FetchResult.new(response: response, freshly_fetched?: freshly_fetched) }

    let(:response) { double("Response") }

    context "when data was freshly fetched from GitLab" do
      let(:freshly_fetched) { true }

      it "returns the response" do
        expect(result.response).to eq(response)
      end

      it "marks the result as freshly fetched" do
        expect(result.freshly_fetched?).to be true
      end
    end

    context "when data was returned from cache" do
      let(:freshly_fetched) { false }

      it "returns the response" do
        expect(result.response).to eq(response)
      end

      it "marks the result as not freshly fetched" do
        expect(result.freshly_fetched?).to be false
      end
    end
  end
end
