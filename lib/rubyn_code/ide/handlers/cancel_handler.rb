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
          session_id = params["sessionId"]

          unless session_id
            return { "cancelled" => false, "error" => "Missing sessionId" }
          end

          # Delegate to the PromptHandler which owns the session threads
          prompt_handler = @server.handler_instance(:prompt)
          if prompt_handler
            prompt_handler.cancel_session(session_id)
          end

          { "cancelled" => true, "sessionId" => session_id }
        end
      end
    end
  end
end
