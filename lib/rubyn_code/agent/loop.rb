# frozen_string_literal: true

require_relative 'system_prompt_builder'
require_relative 'response_parser'
require_relative 'tool_processor'
require_relative 'background_job_handler'
require_relative 'feedback_handler'
require_relative 'llm_caller'

module RubynCode
  module Agent
    class Loop # rubocop:disable Metrics/ClassLength -- core agent loop: LLM calls, tool dispatch, recovery, hooks
      include SystemPromptBuilder
      include ResponseParser
      include ToolProcessor
      include BackgroundJobHandler
      include FeedbackHandler
      include LlmCaller

      MAX_ITERATIONS = Config::Defaults::MAX_ITERATIONS
      GOAL_MAX_ITERATIONS = Config::Defaults::GOAL_MAX_ITERATIONS

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
        @static_prompt_sections = nil
      end

      # @return [Boolean]
      attr_accessor :plan_mode

      # @return [Index::CodebaseIndex, nil]
      attr_reader :codebase_index

      # Send a user message and run the agent loop until a final text
      # response is produced or the iteration limit is reached.
      #
      # @param user_input [String]
      # @param blocks [Array<Hash>, nil] extra content blocks to attach to the
      #   user message (e.g. image blocks from @-mentions). When non-empty the
      #   user message is stored as a mixed content array instead of a string.
      # @return [String] the final assistant text response
      def send_message(user_input, blocks: nil)
        initialize_session!
        check_user_feedback(user_input)
        drain_background_notifications
        inject_skill_listing unless @skills_injected
        @decision_compactor&.detect_topic_switch(user_input)
        @skill_ttl&.tick!
        autoload_triggered_skills(user_input)
        append_user_message(user_input, blocks)
        reset_system_prompt_cache!
        reset_iteration_state

        iteration = 0
        loop do
          result = run_iteration(iteration)
          return result if result

          iteration += 1
          break unless keep_iterating?(iteration)
        end

        RubynCode::Debug.warn("Hit iteration limit (#{iteration})")
        max_iterations_warning(iteration)
      end

      # Append the user turn to the conversation. If image blocks were passed
      # via `blocks:`, the message is stored as a mixed content array with a
      # leading text block and the image blocks appended in order.
      def append_user_message(user_input, blocks)
        if blocks.is_a?(Array) && !blocks.empty?
          content = [{ type: 'text', text: user_input.to_s }, *blocks]
          @conversation.add_user_message(content)
        else
          @conversation.add_user_message(user_input)
        end
      end

      # @return [Tools::TodoStore] shared checklist store, exposed for the REPL renderer
      attr_reader :todo_store

      # Provider-reported usage plus measured Rubyn context reductions for the
      # current prompt. The IDE transport aggregates these snapshots per chat.
      def usage_snapshot
        compressor = @tool_executor.output_compressor.stats
        tool_tokens_saved = compressor[:tokens_saved].to_i
        compaction_tokens_saved = @context_manager.compaction_tokens_saved.to_i
        {
          input_tokens: @context_manager.total_input_tokens.to_i,
          output_tokens: @context_manager.total_output_tokens.to_i,
          cache_read_tokens: @context_manager.cache_read_tokens.to_i,
          cache_write_tokens: @context_manager.cache_write_tokens.to_i,
          efficiency_saved_tokens: tool_tokens_saved + compaction_tokens_saved,
          savings: {
            tool_output_compression: tool_tokens_saved,
            context_compaction: compaction_tokens_saved
          }
        }
      end

      # Apply a one-shot model override for the duration of the next LLM call.
      # Used by `Context#with_optional_model` for custom-command frontmatter.
      def model_override=(model_name)
        stripped = model_name.to_s.strip
        @model_override = stripped.empty? ? nil : stripped
      end

      # Restrict the available tool set for the next LLM call only.
      # @param allowed [Array<String>, nil] tool names, or nil to clear the override.
      def allowed_tools_override=(allowed)
        @allowed_tools_override = allowed.is_a?(Array) && !allowed.empty? ? allowed : nil
      end

      private

      # Overrides the region above. The internal helpers below are private.

      # Decide whether the loop should run another iteration after `iteration`
      # turns. Normally capped at MAX_ITERATIONS, but while a Stop hook (e.g. an
      # active /goal) is keeping the agent alive we extend up to a hard ceiling
      # — a goal can need more tool turns than a single request. The GoalHook's
      # own max-attempts valve terminates an unsatisfiable goal; the ceiling is
      # only a runaway guard.
      def keep_iterating?(iteration)
        return true if iteration < MAX_ITERATIONS

        @stop_block_active && iteration < GOAL_MAX_ITERATIONS
      end

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
        @skill_matcher      = opts[:skill_matcher]
        @web_skill_autoload = opts[:web_skill_autoload]
        @project_root       = opts[:project_root]
        @tool_wrapper       = opts[:tool_wrapper]
        @decision_compactor = build_decision_compactor
        @skill_ttl          = Skills::TtlManager.new
        @todo_store         = opts.fetch(:todo_store, Tools::TodoStore.new)
        @tool_executor.todo_store = @todo_store
        @session_initialized = false
      end

      def build_decision_compactor
        Context::DecisionCompactor.new(context_manager: @context_manager)
      rescue StandardError
        nil
      end

      # One-time session initialization: build project profile and
      # codebase index so the AI doesn't have to explore from scratch.
      def initialize_session!
        return if @session_initialized || !@project_root

        @todo_store&.clear
        @session_initialized = true
        build_project_profile!
        build_codebase_index!
      end

      def build_project_profile!
        profile = Config::ProjectProfile.new(project_root: @project_root)
        profile.load_or_detect!
        RubynCode::Debug.agent("Project profile loaded (#{profile.data.size} keys)")
      rescue StandardError => e
        RubynCode::Debug.warn("Project profile failed: #{e.message}")
      end

      def build_codebase_index!
        index = Index::CodebaseIndex.new(project_root: @project_root)
        index.load_or_build!
        @codebase_index = index
        RubynCode::Debug.agent("Codebase index: #{index.stats[:nodes]} nodes, #{index.stats[:files_indexed]} files")
      rescue StandardError => e
        RubynCode::Debug.warn("Codebase index failed: #{e.message}")
      end

      def assign_callbacks(opts)
        @on_tool_call          = opts[:on_tool_call]
        @on_tool_result        = opts[:on_tool_result]
        @on_text               = opts[:on_text]
        @on_skills_autoloaded  = opts[:on_skills_autoloaded]
        @skills_injected = false
      end

      def reset_iteration_state
        @max_tokens_override   = nil
        @output_recovery_count = 0
        @task_budget_remaining = nil
        @stop_block_active     = false # true while a Stop hook keeps us going
        @allowed_tools_override = nil   # set by Context#with_allowed_tools
        @model_override         = nil   # set by Context#with_optional_model
      end

      def run_iteration(iteration)
        log_iteration(iteration)
        @context_manager.advance_turn!
        compact_if_needed # ensure context is under threshold before LLM call
        response = call_llm
        return handle_refusal(response) if extract_stop_reason(response) == 'refusal'

        tool_calls = extract_tool_calls(response)
        log_response(response, tool_calls)

        return handle_text_response(response) if tool_calls.empty?

        handle_tool_response(response, tool_calls, iteration)
      end

      # Claude's safety classifiers declined the request outright (HTTP 200,
      # stop_reason: "refusal"). Surface a clear message instead of falling
      # through to text/empty-response handling, which would misread the
      # empty or partial content as "waiting on background jobs".
      def handle_refusal(response)
        details = extract_stop_details(response)
        category = details.is_a?(Hash) ? (details['category'] || details[:category]) : nil
        RubynCode::Debug.llm("Refusal: category=#{category || 'unknown'}")

        message = "Claude's safety system declined this request (category: #{category || 'unknown'})."
        @conversation.add_assistant_message([{ type: 'text', text: message }])
        message
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

        return handle_empty_response if text.strip.empty?

        @conversation.add_assistant_message(response_content(response))

        # Stop hook: a hook may block stopping (e.g. an active /goal). When
        # blocked, the reason is injected as user feedback and the loop keeps
        # iterating instead of returning the final text. While blocked, the
        # loop is allowed to run past MAX_ITERATIONS (see #keep_iterating?).
        @stop_block_active = stop_blocked?(text)
        return nil if @stop_block_active

        # Decision-based compaction (topic switch, milestone)
        @decision_compactor&.check!(@conversation)

        # Compact after the response if context is over threshold
        compact_if_needed

        text
      end

      # Fires the :stop hook. If a hook blocks (returns { block: true }), the
      # reason is appended as a user message so the next iteration acts on it.
      #
      # @return [Boolean] true if stopping was blocked (keep iterating)
      def stop_blocked?(text)
        decision = @hook_runner.fire(:stop, conversation: @conversation, response_text: text)
        return false unless decision.is_a?(Hash) && decision[:block]

        RubynCode::Debug.agent('Stop blocked by hook — continuing')
        @conversation.add_user_message(decision[:reason])
        true
      end

      # Empty LLM response (0 content blocks). Common after dispatching
      # background_run — the LLM has nothing to say until results arrive.
      # Wait briefly for jobs, then either continue or accept the empty response.
      def handle_empty_response
        RubynCode::Debug.llm('Empty response — waiting for background jobs')
        sleep 2 # give jobs a moment to register as active
        drain_background_notifications

        if pending_background_jobs?
          wait_for_background_jobs
          nil # keep iterating — job results are now in conversation
        else
          RubynCode::Debug.llm('No background jobs — accepting empty response')
          '' # return empty string to stop the loop
        end
      end

      def handle_tool_response(response, tool_calls, iteration)
        if truncated?(response) && !@max_tokens_override
          escalate_max_tokens
          return nil
        end

        @conversation.add_assistant_message(get_content(response))
        process_tool_calls(tool_calls)
        drain_background_notifications
        @decision_compactor&.check!(@conversation)
        run_maintenance(iteration)
        nil
      end

      # Check if context needs compaction. Runs before LLM calls and
      # after text responses — mirrors Claude Code's "pause for compaction"
      # behavior that keeps context manageable in long sessions.
      def compact_if_needed
        return unless @context_manager.needs_compaction?(@conversation)

        est = @context_manager.estimated_tokens(@conversation)
        RubynCode::Debug.token(
          "Context over threshold (#{est}) — running compaction"
        )
        @context_manager.check_compaction!(@conversation)

        after = @context_manager.estimated_tokens(@conversation)
        RubynCode::Debug.token("Compacted: #{est} → #{after} tokens")
      rescue StandardError => e
        RubynCode::Debug.warn("Compaction failed: #{e.message}")
      end

      def escalate_max_tokens
        RubynCode::Debug.recovery(
          'Tier 1: Escalating max_tokens from ' \
          "#{Config::Defaults::CAPPED_MAX_OUTPUT_TOKENS} to " \
          "#{Config::Defaults::ESCALATED_MAX_OUTPUT_TOKENS}"
        )
        @max_tokens_override = Config::Defaults::ESCALATED_MAX_OUTPUT_TOKENS
      end

      def max_iterations_warning(limit = MAX_ITERATIONS)
        warning = "Reached maximum iteration limit (#{limit}). " \
                  'The conversation may be incomplete. Please review the ' \
                  'current state and continue if needed.'
        @conversation.add_assistant_message([{ type: 'text', text: warning }])
        warning
      end
    end
  end
end
