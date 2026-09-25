require "rails_helper"

RSpec.describe CacheConcern do
  let(:klass) { Class.new { include CacheConcern } }

  describe ".monthly_merged_mr_stats_cache_validity", :freeze_time do
    subject(:validity) { klass.monthly_merged_mr_stats_cache_validity(month) }

    context "with the current month" do
      let(:month) { Date.current.beginning_of_month }

      it { is_expected.to eq(CacheConcern::MONTHLY_GRAPH_CACHE_VALIDITY) }
    end

    context "with a completed month" do
      let(:month) { 1.month.ago.to_date.beginning_of_month }

      it { is_expected.to eq(CacheConcern::COMPLETED_MONTH_STATS_CACHE_VALIDITY) }
    end
  end

  describe ".monthly_merged_mr_stats_cache_key" do
    it "is distinct per month" do
      expect(klass.monthly_merged_mr_stats_cache_key("user", Date.new(2026, 1, 1)))
        .not_to eq(klass.monthly_merged_mr_stats_cache_key("user", Date.new(2026, 2, 1)))
    end
  end
end
