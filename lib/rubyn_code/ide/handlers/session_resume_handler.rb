# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles the "session/resume" JSON-RPC request.
      #
      # Loads a previously persisted session from SessionPersistence and
      # pre-populates the PromptHandler's conversation cache so that the
      # next prompt continues from where the session left off.
      class SessionResumeHandler
        def initialize(server)
          @server = server
        end

        def call(params)
          session_id = params['sessionId']
          return { 'resumed' => false, 'error' => 'Missing sessionId' } unless session_id

          persistence = @server.session_persistence
          return { 'resumed' => false, 'error' => 'Session persistence not available' } unless persistence

          data = persistence.load_session(session_id)
          return { 'resumed' => false, 'error' => 'Session not found' } unless data

          messages = data[:messages] || []

          # Pre-populate the prompt handler's conversation cache so the next
          # prompt picks up from the restored history.
          prompt = @server.handler_instance(:prompt)
          if prompt
            conversation = Agent::Conversation.new
            messages.each { |msg| conversation.messages << msg }
            prompt.inject_conversation(session_id, conversation)
          end

          { 'resumed' => true, 'sessionId' => session_id, 'messages' => messages }
        end
      end
    end
  end
end
