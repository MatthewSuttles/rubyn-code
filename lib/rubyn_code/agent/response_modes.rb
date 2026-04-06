# frozen_string_literal: true

module RubynCode
  module Agent
    # Dynamically adjusts response verbosity based on the current task type.
    # Injects mode-specific instructions into the system prompt to reduce
    # unnecessary output tokens without losing useful information.
    module ResponseModes
      MODES = {
        implementing: {
          label: 'implementing',
          instruction: 'Write the code. Brief comment on non-obvious decisions only. No preamble or recap.'
        },
        explaining: {
          label: 'explaining',
          instruction: 'Explain clearly and concisely. Use examples from this codebase when possible.'
        },
        reviewing: {
          label: 'reviewing',
          instruction: 'List findings with severity, file, line. No filler between findings.'
        },
        exploring: {
          label: 'exploring',
          instruction: 'Summarize structure. Use tree format. Note patterns and anti-patterns briefly.'
        },
        debugging: {
          label: 'debugging',
          instruction: 'State most likely cause first. Then evidence. Then fix. No preamble.'
        },
        testing: {
          label: 'testing',
          instruction: 'Write specs directly. Minimal explanation. Only note non-obvious test setup.'
        },
        chatting: {
          label: 'chatting',
          instruction: 'Respond naturally and concisely.'
        }
      }.freeze

      DEFAULT_MODE = :chatting

      class << self
        # Detects the response mode from the user's message content.
        #
        # @param message [String] the user's input
        # @param tool_calls [Array] recent tool calls (for context)
        # @return [Symbol] one of the MODES keys
        def detect(message, tool_calls: []) # rubocop:disable Metrics/CyclomaticComplexity -- mode detection dispatch
          return :implementing if implementation_signal?(message)
          return :debugging    if debugging_signal?(message)
          return :reviewing    if reviewing_signal?(message)
          return :testing      if testing_signal?(message)
          return :exploring    if exploring_signal?(message)
          return :explaining   if explaining_signal?(message)

          recent_tool = tool_calls.last
          return detect_from_tool(recent_tool) if recent_tool

          DEFAULT_MODE
        end

        # Returns the instruction text for a given mode.
        #
        # @param mode [Symbol]
        # @return [String]
        def instruction_for(mode)
          config = MODES.fetch(mode, MODES[DEFAULT_MODE])
          "\n## Response Mode: #{config[:label]}\n#{config[:instruction]}"
        end

        private

        def implementation_signal?(msg)
          msg.match?(/\b(add|create|implement|build|write|generate|make)\b/i) &&
            msg.match?(/\b(method|class|module|function|feature|endpoint|service|model|controller)\b/i)
        end

        def debugging_signal?(msg)
          msg.match?(/\b(fix|bug|error|broken|failing|crash|wrong|issue|problem|debug)\b/i)
        end

        def reviewing_signal?(msg)
          msg.match?(/\b(review|pr|pull request|code review|check|audit)\b/i)
        end

        def testing_signal?(msg)
          msg.match?(/\b(test|spec|rspec|minitest|coverage|assert)\b/i)
        end

        def exploring_signal?(msg)
          msg.match?(/\b(explore|find|search|where|structure|architecture|how does|show me)\b/i)
        end

        def explaining_signal?(msg)
          msg.match?(/\b(explain|why|what is|how does|tell me|describe|understand)\b/i)
        end

        def detect_from_tool(tool_call)
          name = tool_call.is_a?(Hash) ? (tool_call[:name] || tool_call['name']) : tool_call.to_s
          case name.to_s
          when 'run_specs'               then :testing
          when 'write_file', 'edit_file' then :implementing
          when 'grep', 'glob'            then :exploring
          when 'review_pr'               then :reviewing
          else DEFAULT_MODE
          end
        end
      end
    end
  end
end
