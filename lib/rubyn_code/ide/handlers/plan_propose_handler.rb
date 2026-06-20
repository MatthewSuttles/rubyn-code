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
          raise Protocol::JsonRpcError.new(Protocol::INVALID_PARAMS, 'feature is required') if feature.empty?

          proposer = @proposer || Megaplan::PlanProposer.new
          proposer.propose(feature)
        rescue Megaplan::PlanProposer::InvalidProposalError => e
          warn "[PlanProposeHandler] invalid proposal: #{e.message}"
          raise Protocol::JsonRpcError.new(INVALID_PROPOSAL_CODE, e.message)
        end
      end
    end
  end
end
