# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles "plan/interview/answer" — feeds the user's answer into the
      # active InterviewSession, emits the next question OR the final plan
      # via notifications, and returns an empty ack to the extension.
      class PlanInterviewAnswerHandler
        SESSION_NOT_FOUND_CODE = -32_011
        INVALID_INTERVIEW_CODE = -32_010

        def initialize(server)
          @server = server
        end

        def call(params)
          session_id  = params['sessionId'].to_s
          question_id = params['questionId'].to_s
          answer      = params['answer'].to_s

          session = @server.lookup_interview_session(session_id)
          unless session
            raise Protocol::JsonRpcError.new(SESSION_NOT_FOUND_CODE,
                                             "Unknown interview session: #{session_id}")
          end

          outcome = session.answer(question_id, answer)
          emit_outcome(session, outcome)
          {}
        rescue Megaplan::InterviewSession::InvalidAnswerError => e
          raise Protocol::JsonRpcError.new(Protocol::INVALID_PARAMS, e.message)
        rescue Megaplan::InterviewSession::MalformedResponseError,
               Megaplan::PlanProposer::InvalidProposalError => e
          warn "[PlanInterviewAnswerHandler] interview failed: #{e.message}"
          @server.notify('plan/interview/error', {
                           'sessionId' => params['sessionId'],
                           'message' => e.message
                         })
          @server.drop_interview_session(params['sessionId'].to_s)
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
