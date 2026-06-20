# frozen_string_literal: true

module RubynCode
  module Megaplan
    # Drives one CI recovery attempt on a Rubyn-opened PR.
    #
    # Receives the failure context the extension's CiWatcher packaged
    # (trimmed log + phase docs + branch + attempt counts) and asks the
    # agent to push a fix commit. Returns a `recovery_outcome` shape:
    #
    #   { kind: 'fixed' | 'no_fix' | 'errored', commit_sha?, summary? }
    #
    # 'fixed' means the agent identified and committed a fix on the
    # branch. 'no_fix' means the agent looked but couldn't see an
    # obvious correctness fix in the log (escalate to the human).
    # 'errored' means the agent loop itself crashed.
    class CiRecovery
      class RecoveryError < RubynCode::Error; end

      SYSTEM_PROMPT = <<~PROMPT
        You are Rubyn doing CI auto-recovery on a megaplan PR.

        Read the failing job log, identify the root cause, push a fix
        commit to the existing branch. Keep the diff minimal and focused
        — this is not a refactoring opportunity.

        If you can't identify a concrete fix from the log, output exactly:

          NO_FIX_IDENTIFIED: <one-sentence reason>

        Do not invent fixes. Do not "try something" just to try. A clean
        escalation to the human beats a wrong commit any day.
      PROMPT

      def initialize(agent_invoker: nil)
        @agent_invoker = agent_invoker || method(:default_agent_invoker)
      end

      # @param context [Hash] the recovery_ci payload from the extension
      # @return [Hash] recovery_outcome { kind, commit_sha?, summary? }
      def recover(context)
        validate!(context)
        prompt = build_prompt(context)
        result = @agent_invoker.call(prompt, context)
        interpret(result, context)
      rescue StandardError => e
        { 'kind' => 'errored', 'summary' => e.message }
      end

      private

      def validate!(context)
        raise ArgumentError, 'context required' unless context.is_a?(Hash)

        %w[plan_id phase_number branch pr_number trimmed_log attempt_number max_attempts].each do |key|
          raise ArgumentError, "missing #{key}" if context[key].nil?
        end
      end

      def build_prompt(context)
        phase = context['phase'] || {}
        <<~PROMPT
          Auto-recovery attempt #{context['attempt_number']} of #{context['max_attempts']}.

          **PR:** ##{context['pr_number']}
          **Branch:** `#{context['branch']}`
          **Failing check:** #{context['failing_check_name'] || 'unknown'}
          **Commit SHA:** #{context['commit_sha']}

          **Phase #{context['phase_number']} — #{phase['name']}**
          #{phase['summary']}

          **Trimmed log:**
          ```
          #{context['trimmed_log']}
          ```

          Fix the failure on the branch above. If you can't identify a fix,
          respond with `NO_FIX_IDENTIFIED: <reason>` instead.
        PROMPT
      end

      def interpret(result, context)
        text = result.is_a?(Hash) ? (result[:text] || result['text'] || '') : result.to_s
        if text =~ /\bNO_FIX_IDENTIFIED:\s*(.+)$/
          { 'kind' => 'no_fix', 'summary' => Regexp.last_match(1).strip }
        else
          {
            'kind' => 'fixed',
            'summary' => 'Agent recovery attempt completed.',
            'commit_sha' => context['commit_sha']
          }
        end
      end

      def default_agent_invoker(_prompt, _context)
        # Stub for now — real wiring happens in RecoverCiHandler which has
        # an Agent::Loop on hand. The handler injects its own invoker via
        # the constructor.
        raise RecoveryError, 'No agent invoker configured.'
      end
    end
  end
end
