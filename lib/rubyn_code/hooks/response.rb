# frozen_string_literal: true

module RubynCode
  module Hooks
    # Normalized response from an external (Claude Code-style) hook.
    #
    # External hooks communicate control-flow decisions and prompt augmentations
    # back to the agent via JSON. This class wraps the parsed response and
    # provides predicate methods so call sites don't have to know the response
    # shape details.
    #
    # Supported response shapes (any subset can be combined):
    #
    #   { "continue": false, "stopReason": "Denied by policy" }
    #     — ask the agent to stop. stopReason is appended to the conversation.
    #
    #   { "decision": "block", "reason": "rm -rf is forbidden" }
    #     — for PreToolUse only; abort this tool call before it runs.
    #
    #   { "decision": "approve" } or { "decision": undefined }
    #     — allow the call to proceed (default).
    #
    #   {
    #     "hookSpecificOutput": {
    #       "hookEventName": "PreToolUse",
    #       "additionalContext": "Project policy: always run rubocop before commit"
    #     }
    #   }
    #     — additionalContext is injected into the next system prompt / LLM
    #       request so the model sees the hook's guidance.
    #
    #   { "suppressOutput": true }
    #     — UI hook wants to silence default output rendering (e.g. streamed
    #       json progress). Best-effort; honoured by the renderer when present.
    class Response
      # @return [String, nil] reason text for block/stop decisions
      attr_reader :reason

      # @return [String, nil] additionalContext injected into the next LLM call
      attr_reader :additional_context

      attr_reader :hook_event_name, :stop_reason

      def initialize(raw: {})
        @raw = raw || {}
        @decision      = @raw['decision']
        @continue      = @raw.key?('continue') ? @raw['continue'] : true
        @stop_reason   = @raw['stopReason']
        @reason        = @raw['reason']
        @suppress      = @raw['suppressOutput'] == true

        specific = @raw['hookSpecificOutput'].is_a?(Hash) ? @raw['hookSpecificOutput'] : {}
        @hook_event_name = specific['hookEventName']
        @additional_context = specific['additionalContext']
      end

      # @return [Boolean] true if the hook says to abort a PreToolUse call
      def block?
        @decision == 'block'
      end

      # @return [Boolean] true if the hook says to stop the agent entirely
      def stop?
        @continue == false
      end

      # @return [Boolean] true if the hook has context to inject
      def additional_context?
        !@additional_context.nil? && !@additional_context.to_s.empty?
      end

      # @return [Boolean] true if the hook wants output suppressed
      def suppress_output?
        @suppress
      end

      # @return [Hash] the raw JSON response (for debugging/logging)
      def to_h
        @raw
      end
    end
  end
end
