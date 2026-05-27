  # frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles "plan/interview/start" — kicks off a megaplan interview
      # session. Creates the InterviewSession, fires the first LLM turn,
      # and emits either a plan/interview/question or plan/interview/done
      # notification before returning the new sessionId to the extension.
      class PlanInterviewStartHandler
        INVALID_INTERVIEW_CODE = -32_010

        def initialize(server, factory: nil)
          @server = server
          @factory = factory || -> { Megaplan::InterviewSession.new }
        end

        def call(_params)
          session = @factory.call
          @server.register_interview_session(session)
          outcome = session.start
          emit_outcome(session, outcome)
          { 'sessionId' => session.session_id }
        rescue Megaplan::InterviewSession::MalformedResponseError,
               Megaplan::PlanProposer::InvalidProposalError => e
          warn "[PlanInterviewStartHandler] interview failed: #{e.message}"
          raise Protocol::JsonRpcError.new(INVALID_INTERVIEW_CODE, e.message)
        end

        private

        def emit_outcome(session, outcome)
          if outcome.is_a?(Megaplan::InterviewSession::Question)
            @server.notify('plan/interview/question', {
              'sessionId' => session.session_id,
              'questionId' => outcome.id,
              'text' => outcome.text,
              'options' => outcome.options
            })
          else
            @server.notify('plan/interview/done', {
              'sessionId' => session.session_id,
              'plan' => outcome
            })
            @server.drop_interview_session(session.session_id)
          end
        end
      end
    end
  end
end
