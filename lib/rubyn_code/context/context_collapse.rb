# frozen_string_literal: true

module RubynCode
  module Context
    # Lightweight context reduction that removes old conversation turns without
    # calling the LLM. Runs before auto-compact — if collapse alone brings the
    # context under threshold, the expensive LLM summarization is skipped.
    #
    # Keeps the first message (initial user request), the most recent N exchanges,
    # and replaces everything in between with a "[earlier conversation snipped]" marker.
    module ContextCollapse
      SNIP_MARKER = '[%d earlier messages snipped for context efficiency]'
      CHARS_PER_TOKEN = 4

      # Returns a collapsed copy of messages if doing so brings the estimated
      # token count under threshold. Returns nil if collapse isn't sufficient
      # (caller should fall through to full auto-compact).
      #
      # @param messages [Array<Hash>] conversation messages
      # @param threshold [Integer] target token count
      # @param keep_recent [Integer] number of recent messages to preserve
      # @return [Array<Hash>, nil] collapsed messages or nil if not sufficient
      def self.call(messages, threshold:, keep_recent: 6)
        return nil if messages.size <= keep_recent + 2

        # Keep first message + last N messages, snip the middle
        first = messages.first
        recent = messages.last(keep_recent)
        snipped_count = messages.size - keep_recent - 1

        collapsed = [
          first,
          { role: 'user', content: format(SNIP_MARKER, snipped_count) },
          *recent
        ]

        # Only use collapse if it gets us under threshold
        estimated = (JSON.generate(collapsed).length.to_f / CHARS_PER_TOKEN).ceil
        estimated <= threshold ? collapsed : nil
      rescue JSON::GeneratorError
        nil
      end
    end
  end
end
