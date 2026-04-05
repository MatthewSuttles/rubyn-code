# frozen_string_literal: true

module RubynCode
  module Agent
    # Handles LLM chat calls, option building, prompt-too-long recovery,
    # and maintenance tasks (compaction, budget, stall detection).
    module LlmCaller
      private

      def call_llm
        @hook_runner.fire(:pre_llm_call, conversation: @conversation)

        opts = build_llm_opts
        response = @llm_client.chat(**opts)

        @hook_runner.fire(:post_llm_call, response: response, conversation: @conversation)
        track_usage(response)
        update_task_budget(response)
        response
      rescue LLM::Client::PromptTooLongError
        recover_prompt_too_long(opts)
      end

      def build_llm_opts
        opts = {
          messages: @conversation.to_api_format,
          tools: @plan_mode ? read_only_tool_definitions : tool_definitions,
          system: build_system_prompt,
          on_text: @on_text
        }
        opts[:max_tokens] = @max_tokens_override if @max_tokens_override
        if @task_budget_remaining
          opts[:task_budget] = {
            total: UsageTracker::TASK_BUDGET_TOTAL, remaining: @task_budget_remaining
          }
        end
        opts
      end

      def recover_prompt_too_long(opts)
        RubynCode::Debug.recovery(
          '413 prompt too long — running emergency compaction'
        )
        @context_manager.check_compaction!(@conversation)

        response = @llm_client.chat(**opts, messages: @conversation.to_api_format)
        @hook_runner.fire(
          :post_llm_call, response: response, conversation: @conversation
        )
        track_usage(response)
        response
      end

      # ── Maintenance ──────────────────────────────────────────────────

      def run_maintenance(_iteration)
        run_compaction
        check_budget
        check_stall_detection
      end

      def run_compaction
        before = @conversation.length
        est = @context_manager.estimated_tokens(@conversation.messages)
        RubynCode::Debug.token(
          "context=#{est} tokens (~#{before} messages, " \
          "threshold=#{Config::Defaults::CONTEXT_THRESHOLD_TOKENS})"
        )

        @context_manager.check_compaction!(@conversation)
        log_compaction(before, est)
      rescue NoMethodError
        # context_manager does not implement check_compaction! yet
      end

      def log_compaction(before, est)
        after = @conversation.length
        return unless after < before

        new_est = @context_manager.estimated_tokens(@conversation.messages)
        RubynCode::Debug.loop_tick(
          "Compacted: #{before} -> #{after} messages " \
          "(#{est} -> #{new_est} tokens)"
        )
      end

      def check_budget
        return unless @budget_enforcer

        @budget_enforcer.check!
      rescue BudgetExceededError
        raise
      rescue NoMethodError
        # budget_enforcer does not implement check! yet
      end

      def check_stall_detection
        return unless @stall_detector.stalled?

        nudge = @stall_detector.nudge_message
        @conversation.add_user_message(nudge)
        @stall_detector.reset!
      end
    end
  end
end
