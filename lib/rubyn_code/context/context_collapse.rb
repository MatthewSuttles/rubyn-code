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
      def self.call(messages, threshold:, keep_recent: 6) # rubocop:disable Metrics/AbcSize -- anchor detection adds branches
        return nil if messages.size <= keep_recent + 2

        # Always preserve the very first message (may contain critical
        # system-level context like auth shims) AND the first real user
        # message so the agent retains the user's original request.
        anchors = build_anchors(messages)

        recent = messages.last(keep_recent)
        snipped_count = messages.size - keep_recent - anchors.size

        collapsed = [
          *anchors,
          { role: 'user', content: format(SNIP_MARKER, snipped_count) },
          *recent
        ]

        # Only use collapse if it gets us under threshold
        estimated = (JSON.generate(collapsed).length.to_f / CHARS_PER_TOKEN).ceil
        estimated <= threshold ? collapsed : nil
      rescue JSON::GeneratorError
        nil
      end

      # Builds the list of anchor messages to preserve at the top.
      # Always keeps messages[0] (may contain critical system context).
      # If messages[0] is a system injection, also keeps the first real
      # user message so the agent retains the original request.
      def self.build_anchors(messages)
        first = messages.first
        anchors = [first]

        # If the first message is a system injection, find and keep the
        # first real user message too.
        content = first[:content]
        text = content.is_a?(String) ? content : nil
        if text&.start_with?('[system]')
          user_msg = messages[1..].find do |msg|
            msg[:role] == 'user' && !(msg[:content].is_a?(String) && msg[:content].start_with?('[system]'))
          end
          anchors << user_msg if user_msg
        end

        anchors
      end

      private_class_method :build_anchors
    end
  end
end
