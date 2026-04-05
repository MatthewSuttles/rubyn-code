# frozen_string_literal: true

require_relative 'system_prompt_builder'
require_relative 'response_parser'
require_relative 'tool_processor'
require_relative 'background_job_handler'
require_relative 'feedback_handler'
require_relative 'llm_caller'

module RubynCode
  module Agent
    class Loop
      include SystemPromptBuilder
      include ResponseParser
      include ToolProcessor
      include BackgroundJobHandler
      include FeedbackHandler
      include LlmCaller

      MAX_ITERATIONS = Config::Defaults::MAX_ITERATIONS

      # @param opts [Hash] keyword arguments for loop configuration
      # @option opts [LLM::Client]                    :llm_client
      # @option opts [Tools::Executor]                :tool_executor
      # @option opts [Context::Manager]               :context_manager
      # @option opts [Hooks::Runner]                  :hook_runner
      # @option opts [Agent::Conversation]            :conversation
      # @option opts [Symbol]                         :permission_tier
      # @option opts [Permissions::DenyList]          :deny_list
      # @option opts [Observability::BudgetEnforcer]  :budget_enforcer
      # @option opts [Background::Worker]             :background_manager
      # @option opts [Agent::LoopDetector]            :stall_detector
      # @option opts [Proc]                           :on_tool_call
      # @option opts [Proc]                           :on_tool_result
      # @option opts [Proc]                           :on_text
      # @option opts [Object]                         :skill_loader
      # @option opts [String]                         :project_root
      def initialize(**opts)
        assign_dependencies(opts)
        assign_callbacks(opts)
        @plan_mode = false
      end

      # @return [Boolean]
      attr_accessor :plan_mode

      # Send a user message and run the agent loop until a final text
      # response is produced or the iteration limit is reached.
      #
      # @param user_input [String]
      # @return [String] the final assistant text response
      def send_message(user_input)
        check_user_feedback(user_input)
        drain_background_notifications
        inject_skill_listing unless @skills_injected
        @conversation.add_user_message(user_input)
        reset_iteration_state

        MAX_ITERATIONS.times do |iteration|
          result = run_iteration(iteration)
          return result if result
        end

        RubynCode::Debug.warn("Hit MAX_ITERATIONS (#{MAX_ITERATIONS})")
        max_iterations_warning
      end

      private

      def assign_dependencies(opts)
        assign_required_deps(opts)
        assign_optional_deps(opts)
      end

      def assign_required_deps(opts)
        @llm_client      = opts.fetch(:llm_client)
        @tool_executor   = opts.fetch(:tool_executor)
        @context_manager = opts.fetch(:context_manager)
        @hook_runner     = opts.fetch(:hook_runner)
        @conversation    = opts.fetch(:conversation)
        @permission_tier = opts.fetch(:permission_tier, Permissions::Tier::ALLOW_READ)
        @deny_list       = opts.fetch(:deny_list, Permissions::DenyList.new)
      end

      def assign_optional_deps(opts)
        @budget_enforcer    = opts[:budget_enforcer]
        @background_manager = opts[:background_manager]
        @stall_detector     = opts.fetch(:stall_detector, LoopDetector.new)
        @skill_loader       = opts[:skill_loader]
        @project_root       = opts[:project_root]
      end

      def assign_callbacks(opts)
        @on_tool_call   = opts[:on_tool_call]
        @on_tool_result = opts[:on_tool_result]
        @on_text        = opts[:on_text]
        @skills_injected = false
      end

      def reset_iteration_state
        @max_tokens_override   = nil
        @output_recovery_count = 0
        @task_budget_remaining = nil
      end

      def run_iteration(iteration)
        log_iteration(iteration)
        response   = call_llm
        tool_calls = extract_tool_calls(response)
        log_response(response, tool_calls)

        return handle_text_response(response) if tool_calls.empty?

        handle_tool_response(response, tool_calls, iteration)
      end

      def log_iteration(iteration)
        RubynCode::Debug.loop_tick(
          "iteration=#{iteration} messages=#{@conversation.length} " \
          "max_tokens_override=#{@max_tokens_override || 'default'}"
        )
      end

      def log_response(response, tool_calls)
        stop_reason = extract_stop_reason(response)
        RubynCode::Debug.llm(
          "stop_reason=#{stop_reason} tool_calls=#{tool_calls.size} " \
          "content_blocks=#{get_content(response).size}"
        )
      end

      def handle_text_response(response)
        if truncated?(response)
          RubynCode::Debug.recovery(
            'Text response truncated, entering recovery'
          )
          response = recover_truncated_response(response)
        end

        # Wait for background jobs before finalizing
        if pending_background_jobs?
          @conversation.add_assistant_message(response_content(response))
          wait_for_background_jobs
          return nil # signal: keep iterating
        end

        text = extract_response_text(response)

        # Empty response — the LLM had nothing to say (often after
        # dispatching background jobs). Keep iterating to pick up results.
        if text.strip.empty?
          RubynCode::Debug.llm('Empty response — retrying')
          return nil
        end

        @conversation.add_assistant_message(response_content(response))
        text
      end

      def handle_tool_response(response, tool_calls, iteration)
        if truncated?(response) && !@max_tokens_override
          escalate_max_tokens
          return nil
        end

        @conversation.add_assistant_message(get_content(response))
        process_tool_calls(tool_calls)
        drain_background_notifications
        run_maintenance(iteration)
        nil
      end

      def escalate_max_tokens
        RubynCode::Debug.recovery(
          'Tier 1: Escalating max_tokens from ' \
          "#{Config::Defaults::CAPPED_MAX_OUTPUT_TOKENS} to " \
          "#{Config::Defaults::ESCALATED_MAX_OUTPUT_TOKENS}"
        )
        @max_tokens_override = Config::Defaults::ESCALATED_MAX_OUTPUT_TOKENS
      end

      def max_iterations_warning
        warning = "Reached maximum iteration limit (#{MAX_ITERATIONS}). " \
                  'The conversation may be incomplete. Please review the ' \
                  'current state and continue if needed.'
        @conversation.add_assistant_message([{ type: 'text', text: warning }])
        warning
      end
    end
  end
end
