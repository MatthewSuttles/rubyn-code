# frozen_string_literal: true

require "json"

module RubynCode
  module Context
    # Facade that coordinates the three compaction strategies: micro (every turn),
    # auto (when threshold is exceeded), and manual (user-triggered via /compact).
    class Compactor
      CHARS_PER_TOKEN = 4

      # @param llm_client [#chat, nil] LLM client for summarization-based compaction
      # @param threshold [Integer] estimated token count that triggers auto-compaction
      # @param transcript_dir [String, nil] directory to persist transcripts before compaction
      def initialize(llm_client:, threshold: 50_000, transcript_dir: nil)
        @llm_client = llm_client
        @threshold = threshold
        @transcript_dir = transcript_dir
      end

      # Runs zero-cost micro-compaction on old tool results. Mutates messages
      # in place and returns the count of compacted results.
      #
      # @param messages [Array<Hash>] conversation messages
      # @return [Integer] number of tool results compacted
      def micro_compact!(messages)
        MicroCompact.call(messages)
      end

      # Runs LLM-driven auto-compaction, replacing the full conversation with a
      # continuity summary. Returns a new messages array.
      #
      # @param messages [Array<Hash>] conversation messages
      # @return [Array<Hash>] compacted messages (single summary message)
      # @raise [RubynCode::Error] if no LLM client is configured
      def auto_compact!(messages)
        ensure_llm_client!

        AutoCompact.call(
          messages,
          llm_client: @llm_client,
          transcript_dir: @transcript_dir
        )
      end

      # Runs LLM-driven manual compaction, optionally guided by a focus prompt.
      # Returns a new messages array.
      #
      # @param messages [Array<Hash>] conversation messages
      # @param focus [String, nil] optional user-supplied focus to guide summarization
      # @return [Array<Hash>] compacted messages (single summary message)
      # @raise [RubynCode::Error] if no LLM client is configured
      def manual_compact!(messages, focus: nil)
        ensure_llm_client!

        ManualCompact.call(
          messages,
          llm_client: @llm_client,
          transcript_dir: @transcript_dir,
          focus: focus
        )
      end

      # Checks whether the estimated token count for the messages exceeds the
      # configured threshold.
      #
      # @param messages [Array<Hash>] conversation messages
      # @return [Boolean]
      def should_auto_compact?(messages)
        estimated_tokens(messages) > @threshold
      end

      private

      def estimated_tokens(messages)
        json = JSON.generate(messages)
        (json.length.to_f / CHARS_PER_TOKEN).ceil
      rescue JSON::GeneratorError
        0
      end

      def ensure_llm_client!
        return if @llm_client

        raise RubynCode::Error, "LLM client is required for summarization-based compaction"
      end
    end
  end
end
