# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles "plan/interview/cancel" — drops the named InterviewSession.
      # Notification handler (no id), so it never sends a response. Unknown
      # sessionIds are no-ops; the extension treats cancel as best-effort.
      class PlanInterviewCancelHandler
        def initialize(server)
          @server = server
        end

        def call(params)
          session_id = params['sessionId'].to_s
          @server.drop_interview_session(session_id)
          nil
        end
      end
    end
  end
end
