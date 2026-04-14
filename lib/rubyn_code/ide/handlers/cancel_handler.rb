# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles the "cancel" JSON-RPC request.
      #
      # Signals the agent loop thread for the given session to stop,
      # then returns confirmation.
      class CancelHandler
        def initialize(server)
          @server = server
        end

        def call(params)
          session_id = params['sessionId']

          return { 'cancelled' => false, 'error' => 'Missing sessionId' } unless session_id

          # Delegate to the PromptHandler which owns the session threads
          prompt_handler = @server.handler_instance(:prompt)
          prompt_handler&.cancel_session(session_id)

          # Fire the stop hook so extensions can react to session cancellation
          fire_stop_hook(session_id)

          { 'cancelled' => true, 'sessionId' => session_id }
        end

        private

        def fire_stop_hook(session_id)
          hook_registry = Hooks::Registry.new
          hook_runner = Hooks::Runner.new(registry: hook_registry)
          Hooks::BuiltIn.register_all!(hook_registry)
          hook_runner.fire(:stop, session_id: session_id)
        end
      end
    end
  end
end
