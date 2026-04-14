# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles the "session/reset" JSON-RPC request.
      #
      # Called when the user clicks "New Session" in the chat UI. Delegates
      # to PromptHandler#reset_session which cancels any in-flight agent
      # thread for that sessionId and drops the cached Agent::Conversation,
      # so the next prompt starts with empty message history — parity with
      # the CLI REPL's `/new` command.
      class SessionResetHandler
        def initialize(server)
          @server = server
        end

        def call(params)
          session_id = params['sessionId']
          return { 'reset' => false, 'error' => 'Missing sessionId' } unless session_id

          prompt = @server.handler_instance(:prompt)
          return { 'reset' => false, 'error' => 'Prompt handler not available' } unless prompt

          prompt.reset_session(session_id)
          { 'reset' => true, 'sessionId' => session_id }
        end
      end
    end
  end
end
