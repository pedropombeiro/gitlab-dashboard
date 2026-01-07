# frozen_string_literal: true

require "rails_helper"

RSpec.describe FetchMergeRequestsService do
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
