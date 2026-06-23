# frozen_string_literal: true

module RubynCode
  module Hooks
    # Maps between internal hook event names (snake_case symbols used by the
    # in-process Hooks::Runner) and the Claude Code hook event names
    # (CamelCase strings used by external hooks configured in settings.json).
    #
    # Internal hooks fire at these 7 sites:
    #   :pre_tool_use       — agent/tool_processor.rb#execute_tool
    #   :post_tool_use      — agent/tool_processor.rb#execute_tool
    #   :pre_llm_call       — agent/llm_caller.rb
    #   :post_llm_call      — agent/llm_caller.rb
    #   :stop               — agent/loop.rb#stop_blocked?
    #   :session_start      — ide/handlers/prompt_handler.rb (IDE)
    #   :user_prompt_submit — ide/handlers/prompt_handler.rb (IDE)
    #
    # External hooks (Claude Code parity) consume these 9 event names:
    #   PreToolUse, PostToolUse, UserPromptSubmit, SessionStart,
    #   SessionEnd, Stop, SubagentStop, PreCompact, Notification
    module EventMap
      # Internal symbol => external string
      TO_EXTERNAL = {
        pre_tool_use: 'PreToolUse',
        post_tool_use: 'PostToolUse',
        pre_llm_call: 'PreCompact',
        post_llm_call: 'Notification',
        on_session_end: 'SessionEnd',
        session_start: 'SessionStart',
        user_prompt_submit: 'UserPromptSubmit',
        stop: 'Stop',
        on_subagent_stop: 'SubagentStop'
      }.freeze

      # External string => internal symbol
      TO_INTERNAL = TO_EXTERNAL.invert.freeze

      # Every external event name the dispatcher knows about.
      EXTERNAL_EVENTS = TO_EXTERNAL.values.freeze

      module_function

      # @param internal [Symbol]
      # @return [String, nil]
      def external(internal)
        TO_EXTERNAL[internal.to_sym]
      end

      # @param external [String, Symbol]
      # @return [Symbol, nil]
      def internal(external)
        TO_INTERNAL[external.to_s]
      end
    end
  end
end
