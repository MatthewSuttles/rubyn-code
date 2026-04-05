# frozen_string_literal: true

require 'digest'

module RubynCode
  module Agent
    class LoopDetector
      # @param window [Integer] number of recent calls to keep in the sliding window
      # @param threshold [Integer] number of identical signatures that indicate a stall
      # @param name_window [Integer] larger window for tool name repetition detection
      # @param name_threshold [Integer] how many times the same tool name in name_window triggers stall
      def initialize(window: 5, threshold: 3, name_window: 12, name_threshold: 6)
        @window         = window
        @threshold      = threshold
        @name_window    = name_window
        @name_threshold = name_threshold
        @history        = []
        @name_history   = []
        @file_edits     = Hash.new(0)
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

        # Track tool name frequency separately
        @name_history << tool_name.to_s
        @name_history.shift while @name_history.length > @name_window

        # Track file edit frequency
        return unless %w[edit_file write_file].include?(tool_name.to_s) && tool_input.is_a?(Hash)

        path = tool_input[:path] || tool_input['path']
        @file_edits[path.to_s] += 1 if path
      end

      # Returns true when the same tool call signature appears at least
      # +threshold+ times within the current sliding window.
      #
      # @return [Boolean]
      def stalled?
        # Check 1: Exact same tool call repeated
        if @history.length >= @threshold
          counts = @history.tally
          return true if counts.any? { |_sig, count| count >= @threshold }
        end

        # Check 2: Same tool NAME called too frequently (even with different inputs)
        if @name_history.length >= @name_threshold
          name_counts = @name_history.tally
          return true if name_counts.any? { |_name, count| count >= @name_threshold }
        end

        # Check 3: Same file edited 3+ times
        return true if @file_edits.any? { |_path, count| count >= 3 }

        false
      end

      # Clear recorded history.
      #
      # @return [void]
      def reset!
        @history.clear
        @name_history.clear
        @file_edits.clear
      end

      # A system-level nudge message to inject when a stall is detected.
      # This tells the agent to try a different approach.
      #
      # @return [String]
      def nudge_message
        'You appear to be repeating the same tool call without making progress. ' \
          'Please try a different approach, use a different tool, or ask the user ' \
          'for clarification. Do not repeat the same action.'
      end

      private

      def signature(tool_name, tool_input)
        input_str = case tool_input
                    when Hash   then stable_hash(tool_input)
                    when String then tool_input
                    else ''
                    end

        "#{tool_name}:#{Digest::SHA256.hexdigest(input_str)[0, 16]}"
      end

      # Produce a deterministic string representation of a hash regardless of
      # key insertion order.
      def stable_hash(hash)
        hash.sort_by { |k, _| k.to_s }
            .map { |k, v| "#{k}=#{v}" }
            .join('&')
      end
    end
  end
end
