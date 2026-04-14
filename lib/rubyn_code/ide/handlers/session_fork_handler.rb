# frozen_string_literal: true

require 'securerandom'

module RubynCode
  module IDE
    module Handlers
      # Handles the "session/fork" JSON-RPC request.
      #
      # Loads an existing session, truncates its messages at the given index,
      # and saves the truncated history as a brand-new session. The original
      # session is left untouched.
      class SessionForkHandler
        def initialize(server)
          @server = server
        end

        def call(params)
          session_id = params['sessionId']
          message_index = params['messageIndex']

          return { 'forked' => false, 'error' => 'Missing sessionId' } unless session_id
          return { 'forked' => false, 'error' => 'Missing messageIndex' } unless message_index

          persistence = @server.session_persistence
          return { 'forked' => false, 'error' => 'Session persistence not available' } unless persistence

          data = persistence.load_session(session_id)
          return { 'forked' => false, 'error' => 'Session not found' } unless data

          messages = data[:messages] || []
          truncated = messages[0, message_index.to_i]

          new_session_id = SecureRandom.uuid
          persistence.save_session(
            session_id: new_session_id,
            project_path: data[:project_path] || '',
            messages: truncated,
            title: data[:title] ? "Fork of #{data[:title]}" : nil,
            model: data[:model],
            metadata: { message_count: truncated.size, forked_from: session_id }
          )

          { 'forked' => true, 'newSessionId' => new_session_id }
        end
      end
    end
  end
end
