# frozen_string_literal: true

require 'json'

module RubynCode
  module Context
    # Orchestrates context management for a session. Tracks cumulative token
    # usage from LLM responses and triggers compaction strategies when the
    # estimated context size exceeds the configured threshold.
    class Manager
      CHARS_PER_TOKEN = 4

      attr_reader :total_input_tokens, :total_output_tokens, :current_turn

      # @param threshold [Integer] estimated token count that triggers auto-compaction
      # @param llm_client [LLM::Client, nil] needed for LLM-driven compaction
      def initialize(threshold: Config::Defaults::CONTEXT_THRESHOLD_TOKENS, llm_client: nil)
        @threshold = threshold
        @llm_client = llm_client
        @total_input_tokens = 0
        @total_output_tokens = 0
        @last_compaction_turn = -1
        @current_turn = 0
      end

      attr_writer :llm_client

      # Advances the turn counter. Call once per iteration so that
      # duplicate compaction calls within the same turn are skipped.
      def advance_turn!
        @current_turn += 1
      end

      # Accumulates token counts from an LLM response usage object.
      #
      # @param usage [LLM::Usage, #input_tokens] usage data from an LLM response
      def track_usage(usage)
        @total_input_tokens += usage.input_tokens.to_i
        @total_output_tokens += usage.output_tokens.to_i
      end

      # Rough estimate of token count for a set of messages based on their
      # JSON-serialized character length (~4 chars per token).
      #
      # @param messages [Array<Hash>] conversation messages
      # @return [Integer] estimated token count
      def estimated_tokens(messages)
        json = JSON.generate(messages)
        (json.length.to_f / CHARS_PER_TOKEN).ceil
      rescue JSON::GeneratorError
        0
      end

      # Returns true if the estimated token count exceeds the threshold.
      #
      # @param messages [Array<Hash>] conversation messages
      # @return [Boolean]
      def needs_compaction?(messages)
        estimated_tokens(messages) > @threshold
      end

      # Runs micro-compaction every turn and auto-compaction when the context
      # exceeds the threshold. Expects a conversation object that responds to
      # #messages and #messages= (or #replace_messages).
      #
      # @param conversation [#messages, #messages=] conversation wrapper
      # @return [void]
      # Fraction of the compaction threshold at which micro-compact kicks in.
      # Running it too early busts the prompt cache prefix (mutated messages
      # change the hash, invalidating server-side cached tokens).
      # Anthropic has prompt caching so we delay compaction (0.7).
      # OpenAI has no cache prefix to protect so we compact earlier (0.5).
      MICRO_COMPACT_RATIO_CACHED = 0.7
      MICRO_COMPACT_RATIO_UNCACHED = 0.5

      def check_compaction!(conversation)
        # Guard: skip if compaction already ran this turn
        return if @last_compaction_turn == @current_turn

        @last_compaction_turn = @current_turn

        messages = conversation.messages

        # Step 1: Zero-cost micro-compact — but only when we're approaching
        # the compaction threshold. Running it every turn mutates old messages,
        # which invalidates the prompt cache prefix and wastes tokens.
        est = estimated_tokens(messages)
        MicroCompact.call(messages) if est > (@threshold * micro_compact_ratio)

        return unless needs_compaction?(messages)

        # Step 2: Try context collapse (snip old messages, no LLM call)
        collapsed = ContextCollapse.call(messages, threshold: @threshold)
        if collapsed
          apply_compacted_messages(conversation, collapsed)
          return
        end

        # Step 3: Full LLM-driven auto-compact (expensive, last resort)
        return unless @llm_client

        compactor = Compactor.new(llm_client: @llm_client, threshold: @threshold)
        new_messages = compactor.auto_compact!(messages)
        apply_compacted_messages(conversation, new_messages)
      end

      # Resets cumulative token counters to zero.
      #
      # @return [void]
      def reset!
        @total_input_tokens = 0
        @total_output_tokens = 0
        @last_compaction_turn = -1
        @current_turn = 0
      end

      private

      # Returns the micro-compact ratio based on the active provider.
      # Providers with prompt caching (Anthropic) use a higher ratio to
      # preserve cached prefixes; providers without caching compact earlier.
      def micro_compact_ratio
        return MICRO_COMPACT_RATIO_UNCACHED if uncached_provider?

        MICRO_COMPACT_RATIO_CACHED
      end

      def uncached_provider?
        return false unless @llm_client

        provider = @llm_client.provider_name if @llm_client.respond_to?(:provider_name)
        %w[openai openai_compatible].include?(provider)
      end

      def apply_compacted_messages(conversation, new_messages)
        if conversation.respond_to?(:replace_messages)
          conversation.replace_messages(new_messages)
        elsif conversation.respond_to?(:messages=)
          conversation.messages = new_messages
        end
      end
    end
  end
end
