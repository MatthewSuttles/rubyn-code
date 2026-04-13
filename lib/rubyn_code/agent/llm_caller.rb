# frozen_string_literal: true

module RubynCode
  module Agent
    # Handles LLM chat calls, option building, prompt-too-long recovery,
    # and maintenance tasks (compaction, budget, stall detection).
    module LlmCaller # rubocop:disable Metrics/ModuleLength -- LLM call pipeline with routing + recovery
      private

      def call_llm
        @hook_runner.fire(:pre_llm_call, conversation: @conversation)

        opts = build_llm_opts
        log_llm_call(opts)
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
        opts[:model] = routed_model
        if @task_budget_remaining
          opts[:task_budget] = {
            total: UsageTracker::TASK_BUDGET_TOTAL, remaining: @task_budget_remaining
          }
        end
        opts
      end

      # Uses ModelRouter to pick the right model for the current task.
      # Only returns models from the active provider — never crosses
      # provider boundaries (e.g., won't send a GPT model to Anthropic).
      # Falls back to nil (use client's default) if routing fails.
      def routed_model # rubocop:disable Metrics/CyclomaticComplexity -- guard clauses for provider/mode checks
        return nil if manual_model_mode?

        last_user = last_user_message_text
        return nil unless last_user

        recent = @stall_detector.respond_to?(:recent_tools) ? @stall_detector.recent_tools : []
        task = LLM::ModelRouter.detect_task(last_user, recent_tools: recent)
        resolved = LLM::ModelRouter.resolve(task, client: @llm_client)

        # Only use the routed model if it's from the same provider
        active = @llm_client.respond_to?(:provider_name) ? @llm_client.provider_name : nil
        return nil if active && resolved[:provider] != active

        resolved[:model]
      rescue StandardError
        nil
      end

      def manual_model_mode?
        Config::Settings.new.get('model_mode', 'auto') == 'manual'
      rescue StandardError
        false
      end

      def last_user_message_text
        msg = @conversation.messages.reverse_each.find { |m| m[:role] == 'user' }
        return nil unless msg

        content = msg[:content]
        content.is_a?(String) ? content : nil
      end

      def log_llm_call(opts) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity -- safe accessor checks
        default_model = @llm_client.respond_to?(:model) ? @llm_client.model : 'default'
        routed = opts[:model]
        effective = routed || default_model
        provider = @llm_client.respond_to?(:provider_name) ? @llm_client.provider_name : 'unknown'
        tool_count = opts[:tools]&.size || 0
        routed_tag = routed && routed != default_model ? " (routed from #{default_model})" : ''
        RubynCode::Debug.llm("chat provider=#{provider} model=#{effective}#{routed_tag} tools=#{tool_count}")
      rescue StandardError
        nil
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
