  # frozen_string_literal: true

require 'securerandom'

module RubynCode
  module IDE
    module Handlers
      # Handles the "recover_ci" JSON-RPC request.
      #
      # Takes the recovery context the extension packaged (failing log,
      # phase docs, branch, attempt counts) and runs the agent against
      # it. Returns the recovery_outcome { kind, commit_sha?, summary? }.
      #
      # The handler spawns the actual agent work in a background thread
      # so the JSON-RPC reply can include a sessionId immediately. The
      # extension watches the session via the existing agent/status
      # notifications + a terminal recovery/outcome notification carrying
      # the structured result.
      class RecoverCiHandler
        def initialize(server, recovery: nil)
          @server = server
          @recovery = recovery
        end

        def call(params)
          context = normalize_params(params)
          return error_response('context required') if context.nil?

          session_id = params['sessionId'] || SecureRandom.uuid
          Thread.new do
            run_recovery(session_id, context)
          end
          { 'accepted' => true, 'sessionId' => session_id }
        end

        private

        def run_recovery(session_id, context)
          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'recovering',
                           'phaseNumber' => context['phase_number'],
                           'attemptNumber' => context['attempt_number']
                         })

          recovery = @recovery || Megaplan::CiRecovery.new(
            agent_invoker: build_invoker(session_id)
          )
          outcome = recovery.recover(context)

          @server.notify('recovery/outcome', {
                           'sessionId' => session_id,
                           'planId' => context['plan_id'],
                           'phaseNumber' => context['phase_number'],
                           'kind' => outcome['kind'],
                           'commitSha' => outcome['commit_sha'],
                           'summary' => outcome['summary']
                         })

          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'done',
                           'summary' => outcome['summary']
                         })
        rescue StandardError => e
          warn "[RecoverCiHandler] error: #{e.message}"
          @server.notify('recovery/outcome', {
                           'sessionId' => session_id,
                           'planId' => context['plan_id'],
                           'phaseNumber' => context['phase_number'],
                           'kind' => 'errored',
                           'summary' => e.message
                         })
          @server.notify('agent/status', {
                           'sessionId' => session_id,
                           'status' => 'error',
                           'error' => e.message
                         })
        end

        # Build an agent invoker that routes the recovery prompt through
        # the same Agent::Loop the existing PromptHandler uses, but with
        # the streaming text wired back as agent/status notifications
        # tagged with the recovery session id.
        def build_invoker(session_id)
          lambda do |prompt, _context|
            llm_client = LLM::Client.new
            response = llm_client.chat(
              messages: [{ role: 'user', content: prompt }],
              on_text: ->(text) {
                @server.notify('stream/text', {
                                 'sessionId' => session_id,
                                 'text' => text,
                                 'final' => false
                               })
              }
            )
            response.is_a?(Hash) ? response : { 'text' => response.to_s }
          end
        end

        def normalize_params(params)
          return nil unless params.is_a?(Hash)

          # Accept both snake_case and camelCase keys — the extension
          # produces camelCase, but the LLM-side service uses snake_case
          # internally. Normalize once at the boundary.
          mapping = {
            'planId' => 'plan_id',
            'phaseNumber' => 'phase_number',
            'prNumber' => 'pr_number',
            'failingCheckName' => 'failing_check_name',
            'fullLog' => 'full_log',
            'trimmedLog' => 'trimmed_log',
            'commitSha' => 'commit_sha',
            'attemptNumber' => 'attempt_number',
            'maxAttempts' => 'max_attempts'
          }
          out = params.dup
          mapping.each do |camel, snake|
            out[snake] = out.delete(camel) if out.key?(camel) && !out.key?(snake)
          end
          out
        end

        def error_response(message, code: -32_602)
          { 'error' => { 'code' => code, 'message' => message } }
        end
      end
    end
  end
end
