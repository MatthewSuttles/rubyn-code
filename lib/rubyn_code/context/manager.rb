# frozen_string_literal: true

require "json"

module RubynCode
  module Context
    # Orchestrates context management for a session. Tracks cumulative token
    # usage from LLM responses and triggers compaction strategies when the
    # estimated context size exceeds the configured threshold.
    class Manager
      CHARS_PER_TOKEN = 4

      attr_reader :total_input_tokens, :total_output_tokens

      # @param threshold [Integer] estimated token count that triggers auto-compaction
      def initialize(threshold: 50_000)
        @threshold = threshold
        @total_input_tokens = 0
        @total_output_tokens = 0
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
      def check_compaction!(conversation)
        messages = conversation.messages

        # Step 1: Zero-cost micro-compact (replace old tool results with placeholders)
        MicroCompact.call(messages)

        return unless needs_compaction?(messages)

        # Step 2: Try context collapse (snip old messages, no LLM call)
        collapsed = ContextCollapse.call(messages, threshold: @threshold)
        if collapsed
          apply_compacted_messages(conversation, collapsed)
          return
        end

        # Step 3: Full LLM-driven auto-compact (expensive, last resort)
        compactor = Compactor.new(
          llm_client: conversation.respond_to?(:llm_client) ? conversation.llm_client : nil,
          threshold: @threshold
        )

        new_messages = compactor.auto_compact!(messages)
        apply_compacted_messages(conversation, new_messages)
      end

      # Resets cumulative token counters to zero.
      #
      # @return [void]
      def reset!
        @total_input_tokens = 0
        @total_output_tokens = 0
      end

      private

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
