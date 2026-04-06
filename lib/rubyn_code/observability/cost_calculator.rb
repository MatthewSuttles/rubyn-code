# frozen_string_literal: true

module RubynCode
  module Observability
    # Maps model identifiers and token counts to USD cost.
    #
    # Pricing is based on per-million-token rates. Cache reads are billed at
    # 10% of the input rate; cache writes at 25% of the input rate.
    module CostCalculator
      # Per-million-token rates: { model_prefix => [input_rate, output_rate] }
      PRICING = {
        # Anthropic — Claude 4.6
        'claude-haiku-4-5' => [1.00, 5.00],
        'claude-sonnet-4-6' => [3.00, 15.00],
        'claude-opus-4-6' => [15.00, 75.00],
        # OpenAI — GPT-5.4
        'gpt-5.4' => [2.50, 10.00],
        'gpt-5.4-mini' => [0.15, 0.60],
        'gpt-5.4-nano' => [0.10, 0.40],
        # OpenAI — legacy
        'gpt-4o' => [2.50, 10.00],
        'gpt-4o-mini' => [0.15, 0.60],
        'o3' => [2.00, 8.00],
        'o4-mini' => [1.10, 4.40]
      }.freeze

      CACHE_READ_DISCOUNT  = 0.1
      CACHE_WRITE_PREMIUM  = 1.25

      class << self
        # Calculates the USD cost for a single API call.
        #
        # @param model [String] the model identifier (exact or prefix match)
        # @param input_tokens [Integer] number of input tokens
        # @param output_tokens [Integer] number of output tokens
        # @param cache_read_tokens [Integer] tokens served from cache
        # @param cache_write_tokens [Integer] tokens written to cache
        # @return [Float] cost in USD
        def calculate(model:, input_tokens:, output_tokens:, cache_read_tokens: 0, cache_write_tokens: 0)
          input_rate, output_rate = rates_for(model)

          token_cost(input_tokens, input_rate) +
            token_cost(output_tokens, output_rate) +
            token_cost(cache_read_tokens, input_rate * CACHE_READ_DISCOUNT) +
            token_cost(cache_write_tokens, input_rate * CACHE_WRITE_PREMIUM)
        end

        private

        # Resolves pricing rates for a model, falling back to prefix matching
        # and then a conservative default.
        #
        # @param model [String]
        # @return [Array(Float, Float)] [input_rate, output_rate]
        def token_cost(tokens, rate)
          (tokens.to_f / 1_000_000) * rate
        end

        def rates_for(model)
          # User-configured pricing takes priority
          custom = config_pricing(model)
          return custom if custom

          return PRICING[model] if PRICING.key?(model)

          # Try prefix match (e.g., "claude-sonnet-4-20250514-v2" matches "claude-sonnet-4-20250514")
          PRICING.each do |prefix, rates|
            return rates if model.start_with?(prefix)
          end

          # Conservative fallback: use the most expensive known model
          PRICING.max_by { |_, rates| rates.first }.last
        end

        def config_pricing(model)
          settings = Config::Settings.new
          custom = settings.custom_pricing
          custom[model]
        rescue StandardError
          nil
        end
      end
    end
  end
end
