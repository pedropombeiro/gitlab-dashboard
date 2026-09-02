# frozen_string_literal: true

require "rails_helper"

RSpec.describe MergeRequestsHelper do
  describe "merge time helpers" do
    def merge_request(duration)
      double(createdAt: Time.zone.at(0), mergedAt: Time.zone.at(duration))
    end

    it "returns zero for an empty collection" do
      expect(mean_time_to_merge([])).to eq(0)
      expect(median_time_to_merge([])).to eq(0)
    end

    it "returns the only merge request duration" do
      merge_requests = [merge_request(2.days)]

      expect(mean_time_to_merge(merge_requests)).to eq(2.days)
      expect(median_time_to_merge(merge_requests)).to eq(2.days)
    end

    it "averages the two middle durations for an even collection" do
      merge_requests = [1.day, 2.days, 3.days, 4.days].map { |duration| merge_request(duration) }

      expect(median_time_to_merge(merge_requests)).to eq(2.5.days)
    end

    it "uses the middle duration for an odd collection" do
      merge_requests = [3.days, 1.day, 2.days].map { |duration| merge_request(duration) }

      expect(median_time_to_merge(merge_requests)).to eq(2.days)
    end

    it "is less affected than the mean by an extreme outlier" do
      merge_requests = [1.day, 1.day, 1.day, 100.days].map { |duration| merge_request(duration) }

      expect(mean_time_to_merge(merge_requests)).to eq(25.75.days)
      expect(median_time_to_merge(merge_requests)).to eq(1.day)
    end
  end

  describe "attention-needed helpers" do
    def merge_request(*allow_failure_values)
      jobs = allow_failure_values.map { |allow_failure| double(allowFailure: allow_failure) }
      double(headPipeline: double(failedJobs: double(nodes: jobs)))
    end

    it "counts merge requests with blocking failed jobs" do
      merge_requests = [merge_request(false, false), merge_request(true), merge_request(false, true)]

      expect(attention_needed_merge_requests_count(merge_requests)).to eq(2)
      expect(attention_needed?(merge_requests.first)).to be(true)
      expect(any_failed_pipeline?(merge_requests)).to be(true)
    end

    it "ignores allowed failures and missing pipelines" do
      merge_requests = [merge_request(true), double(headPipeline: nil)]

      expect(attention_needed_merge_requests_count(merge_requests)).to eq(0)
      expect(attention_needed?(merge_requests.first)).to be(false)
      expect(any_failed_pipeline?(merge_requests)).to be(false)
    end
  end
end
