# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Observability::CostCalculator do
  describe '.calculate' do
    it 'returns correct cost for Anthropic sonnet' do
      cost = described_class.calculate(
        model: 'claude-sonnet-5-4',
        input_tokens: 1_000_000,
        output_tokens: 1_000_000
      )
      # $3 input + $15 output = $18
      expect(cost).to be_within(0.01).of(18.0)
    end

    it 'handles haiku pricing' do
      cost = described_class.calculate(
        model: 'claude-haiku-4-5',
        input_tokens: 1_000_000,
        output_tokens: 0
      )
      expect(cost).to be_within(0.01).of(1.0)
    end

    it 'returns correct cost for OpenAI gpt-4o' do
      cost = described_class.calculate(
        model: 'gpt-4o',
        input_tokens: 1_000_000,
        output_tokens: 1_000_000
      )
      # $2.50 input + $10 output = $12.50
      expect(cost).to be_within(0.01).of(12.50)
    end

    it 'returns correct cost for OpenAI gpt-4o-mini' do
      cost = described_class.calculate(
        model: 'gpt-4o-mini',
        input_tokens: 1_000_000,
        output_tokens: 1_000_000
      )
      # $0.15 input + $0.60 output = $0.75
      expect(cost).to be_within(0.01).of(0.75)
    end

    it 'returns a positive cost for unknown model (uses most expensive fallback)' do
      cost = described_class.calculate(
        model: 'future-model-9000',
        input_tokens: 1000,
        output_tokens: 1000
      )
      expect(cost).to be > 0
    end

    it 'accounts for cache read and write tokens' do
      base_cost = described_class.calculate(
        model: 'claude-sonnet-5-4',
        input_tokens: 1000, output_tokens: 0
      )
      cached_cost = described_class.calculate(
        model: 'claude-sonnet-5-4',
        input_tokens: 1000, output_tokens: 0,
        cache_read_tokens: 500, cache_write_tokens: 500
      )
      expect(cached_cost).to be > base_cost
    end

    it 'handles zero cache tokens gracefully (OpenAI models)' do
      cost = described_class.calculate(
        model: 'gpt-4o',
        input_tokens: 1000, output_tokens: 500,
        cache_read_tokens: 0, cache_write_tokens: 0
      )
      expect(cost).to be > 0
    end

    it 'uses config pricing when available' do
      settings = instance_double(RubynCode::Config::Settings, custom_pricing: { 'M1' => [0.50, 2.00] })
      allow(RubynCode::Config::Settings).to receive(:new).and_return(settings)

      cost = described_class.calculate(
        model: 'M1',
        input_tokens: 1_000_000,
        output_tokens: 1_000_000
      )
      # $0.50 input + $2.00 output = $2.50
      expect(cost).to be_within(0.01).of(2.50)
    end

    it 'falls back to hardcoded pricing when config has no match' do
      settings = instance_double(RubynCode::Config::Settings, custom_pricing: {})
      allow(RubynCode::Config::Settings).to receive(:new).and_return(settings)

      cost = described_class.calculate(
        model: 'gpt-4o',
        input_tokens: 1_000_000,
        output_tokens: 1_000_000
      )
      expect(cost).to be_within(0.01).of(12.50)
    end

    it 'returns zero when all token counts are zero' do
      cost = described_class.calculate(
        model: 'claude-sonnet-5-4',
        input_tokens: 0, output_tokens: 0
      )
      expect(cost).to eq(0.0)
    end
  end
end
