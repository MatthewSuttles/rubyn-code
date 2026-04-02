# frozen_string_literal: true

require "spec_helper"

RSpec.describe RubynCode::Observability::CostCalculator do
  describe ".calculate" do
    it "returns correct cost for a known model" do
      cost = described_class.calculate(
        model: "claude-sonnet-4-20250514",
        input_tokens: 1_000_000,
        output_tokens: 1_000_000
      )
      # $3 input + $15 output = $18
      expect(cost).to be_within(0.01).of(18.0)
    end

    it "handles haiku pricing" do
      cost = described_class.calculate(
        model: "claude-haiku-4-5",
        input_tokens: 1_000_000,
        output_tokens: 0
      )
      expect(cost).to be_within(0.01).of(1.0)
    end

    it "returns a positive cost for unknown model (uses most expensive fallback)" do
      cost = described_class.calculate(
        model: "future-model-9000",
        input_tokens: 1000,
        output_tokens: 1000
      )
      expect(cost).to be > 0
    end

    it "accounts for cache read and write tokens" do
      base_cost = described_class.calculate(
        model: "claude-sonnet-4-20250514",
        input_tokens: 1000, output_tokens: 0
      )
      cached_cost = described_class.calculate(
        model: "claude-sonnet-4-20250514",
        input_tokens: 1000, output_tokens: 0,
        cache_read_tokens: 500, cache_write_tokens: 500
      )
      expect(cached_cost).to be > base_cost
    end

    it "returns zero when all token counts are zero" do
      cost = described_class.calculate(
        model: "claude-sonnet-4-20250514",
        input_tokens: 0, output_tokens: 0
      )
      expect(cost).to eq(0.0)
    end
  end
end
