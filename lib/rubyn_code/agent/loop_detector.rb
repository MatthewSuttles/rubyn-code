# frozen_string_literal: true

require "digest"

module RubynCode
  module Agent
    class LoopDetector
      # @param window [Integer] number of recent calls to keep in the sliding window
      # @param threshold [Integer] number of identical signatures that indicate a stall
      def initialize(window: 5, threshold: 3)
        @window    = window
        @threshold = threshold
        @history   = []
      end

      # Record a tool invocation. The signature is derived from the tool name
      # and a stable hash of the input so that identical calls are detected
      # regardless of key ordering.
      #
      # @param tool_name [String]
      # @param tool_input [Hash, String, nil]
      # @return [void]
      def record(tool_name, tool_input)
        sig = signature(tool_name, tool_input)
        @history << sig
        @history.shift while @history.length > @window
      end

      # Returns true when the same tool call signature appears at least
      # +threshold+ times within the current sliding window.
      #
      # @return [Boolean]
      def stalled?
        return false if @history.length < @threshold

        counts = @history.tally
        counts.any? { |_sig, count| count >= @threshold }
      end

      # Clear recorded history.
      #
      # @return [void]
      def reset!
        @history.clear
      end

      # A system-level nudge message to inject when a stall is detected.
      # This tells the agent to try a different approach.
      #
      # @return [String]
      def nudge_message
        "You appear to be repeating the same tool call without making progress. " \
          "Please try a different approach, use a different tool, or ask the user " \
          "for clarification. Do not repeat the same action."
      end

      private

      def signature(tool_name, tool_input)
        input_str = case tool_input
                    when Hash   then stable_hash(tool_input)
                    when String then tool_input
                    else ""
                    end

        "#{tool_name}:#{Digest::SHA256.hexdigest(input_str)[0, 16]}"
      end

      # Produce a deterministic string representation of a hash regardless of
      # key insertion order.
      def stable_hash(hash)
        hash.sort_by { |k, _| k.to_s }
            .map { |k, v| "#{k}=#{v}" }
            .join("&")
      end
    end
  end
end
