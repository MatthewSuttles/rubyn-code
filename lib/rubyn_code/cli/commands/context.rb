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
        :message_handler,
        :hook_registry,
        :checkpoint_manager
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

        # Restrict the tool set for a single agent invocation. The next
        # `send_message` call inside the block sees only the tools in
        # `allowed`; the override is cleared after the call.
        def with_allowed_tools(allowed = nil, &block)
          apply_loop_override(:allowed_tools_override=, allowed, &block)
        end

        # Apply a one-shot model override for the duration of a block.
        def with_optional_model(model_name = nil, &block)
          apply_loop_override(:model_override=, model_name, &block)
        end

        private

        # Set an override on the agent loop (when one is wired in) for the
        # duration of the block, then clear it. Custom commands without
        # a loop (e.g. test doubles) fall through to a plain yield.
        def apply_loop_override(method, value)
          loop = agent_loop
          return yield unless loop.respond_to?(method)

          loop.public_send(method, value)
          yield
        ensure
          loop&.public_send(method, nil) if loop.respond_to?(method)
        end
      end
    end
  end
end
