# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles the "session/list" JSON-RPC request.
      #
      # Returns a list of past sessions from SessionPersistence, optionally
      # filtered by project path. If SessionPersistence is not available
      # (e.g. no database configured), returns an empty sessions array.
      class SessionListHandler
        def initialize(server)
          @server = server
        end

        def call(params)
          persistence = @server.session_persistence
          unless persistence
            return { 'sessions' => [] }
          end

          project_path = params['projectPath']
          limit = params['limit'] || 20

          summaries = persistence.list_sessions(project_path: project_path, limit: limit)

          sessions = summaries.map do |s|
            {
              'id' => s[:id],
              'title' => s[:title],
              'updatedAt' => s[:updated_at],
              'messageCount' => (s[:metadata] || {})[:message_count] || 0
            }
          end

          { 'sessions' => sessions }
        end
      end
    end
  end
end
