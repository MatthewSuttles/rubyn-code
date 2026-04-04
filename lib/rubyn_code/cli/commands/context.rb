# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # Immutable context object passed to every slash command.
      # Provides access to all REPL dependencies without coupling
      # commands to the REPL class itself.
      Context = Data.define(
        :renderer,
        :conversation,
        :agent_loop,
        :context_manager,
        :budget_enforcer,
        :llm_client,
        :db,
        :session_id,
        :project_root,
        :skill_loader,
        :session_persistence,
        :background_worker,
        :permission_tier,
        :plan_mode,
        :message_handler
      ) do
        # Convenience: return a new Context with a message handler attached.
        # Used by commands like /review that delegate to the LLM.
        #
        # @param handler [Proc] the REPL's handle_message proc
        def with_message_handler(handler)
          with(message_handler: handler)
        end

        # @param text [String] message to send through the agent loop
        def send_message(text)
          message_handler&.call(text)
        end

        # @return [Boolean]
        def plan_mode? = plan_mode
      end
    end
  end
end
