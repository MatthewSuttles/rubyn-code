  # frozen_string_literal: true

require 'securerandom'

module RubynCode
  module IDE
    module Handlers
      # Handles the "plan/propose" JSON-RPC request.
      #
      # Synchronous: blocks until the LLM returns a structured plan or
      # raises. The extension shows a progress spinner during the call;
      # plan generation typically takes 5-30s.
      #
      # Response shape mirrors what the extension's PlanManager.toPlan
      # expects: { slug, feature, phases: [{ number, name, slug, summary,
      # requirements_md, design_md, tasks_md }] }.
      class PlanProposeHandler
        # JSON-RPC error code: a clear signal to the extension that the
        # LLM produced an unparseable / malformed plan_proposal. The
        # extension surfaces this with the actual error message.
        INVALID_PROPOSAL_CODE = -32_001

        def initialize(server, proposer: nil)
          @server = server
          @proposer = proposer
        end

        def call(params)
          feature = params['feature'].to_s.strip
          return error_response('feature is required', code: -32_602) if feature.empty?

          proposer = @proposer || Megaplan::PlanProposer.new
          proposer.propose(feature)
        rescue Megaplan::PlanProposer::InvalidProposalError => e
          warn "[PlanProposeHandler] invalid proposal: #{e.message}"
          error_response(e.message, code: INVALID_PROPOSAL_CODE)
        rescue StandardError => e
          warn "[PlanProposeHandler] error: #{e.message}"
          error_response(e.message)
        end

        private

        def error_response(message, code: -32_000)
          { 'error' => { 'code' => code, 'message' => message } }
        end
      end
    end
  end
end
