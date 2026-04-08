# frozen_string_literal: true

require 'securerandom'

module RubynCode
  module Autonomous
    # The GOLEM daemon — an always-on autonomous agent that cycles between
    # working on tasks and polling for new work. The lifecycle is:
    #
    #   spawned → working ⇄ idle → shutting_down → stopped
    #
    # Safety limits (max_runs, max_cost, idle_timeout) prevent runaway execution.
    # Signal traps (SIGTERM, SIGINT) trigger graceful shutdown.
    #
    # Unlike the REPL, the daemon runs a full Agent::Loop per task — meaning
    # it can read files, write code, run specs, and use every tool available.
    class Daemon # rubocop:disable Metrics/ClassLength -- daemon lifecycle + retry + audit + cost
      LIFECYCLE_STATES = %i[spawned working idle shutting_down stopped].freeze
      MAX_TASK_RETRIES = 3

      attr_reader :agent_name, :role, :state, :runs_completed, :total_cost

      # @param agent_name [String] unique name for this daemon instance
      # @param role [String] the agent's role / persona description
      # @param llm_client [LLM::Client] LLM API client
      # @param project_root [String] path to the project being worked on
      # @param task_manager [Tasks::Manager] task persistence layer
      # @param mailbox [Teams::Mailbox] message mailbox
      # @param max_runs [Integer] maximum work cycles before auto-shutdown (default 100)
      # @param max_cost [Float] maximum cumulative LLM cost in USD before auto-shutdown (default 10.0)
      # @param poll_interval [Numeric] idle polling interval in seconds (default 5)
      # @param idle_timeout [Numeric] seconds of idle before shutdown (default 60)
      # @param on_state_change [Proc, nil] callback invoked with (old_state, new_state)
      # @param on_task_complete [Proc, nil] callback invoked with (task, result_text)
      # @param on_task_error [Proc, nil] callback invoked with (task, error)
      # @param session_persistence [Memory::SessionPersistence, nil] optional audit trail persistence
      def initialize( # rubocop:disable Metrics/ParameterLists
        agent_name:, role:, llm_client:, project_root:, task_manager:, mailbox:,
        max_runs: 100, max_cost: 10.0, poll_interval: 5, idle_timeout: 60,
        on_state_change: nil, on_task_complete: nil, on_task_error: nil,
        session_persistence: nil
      )
        assign_core_attrs(agent_name:, role:, llm_client:, project_root:, task_manager:, mailbox:)
        assign_limits(max_runs:, max_cost:, poll_interval:, idle_timeout:)
        assign_callbacks_and_state(on_state_change, on_task_complete, on_task_error)
        @session_persistence = session_persistence
      end

      # Enters the work-idle-work cycle. Blocks the calling thread until
      # the daemon shuts down (via safety limits, idle timeout, or #stop!).
      #
      # @return [Symbol] the final state (:stopped)
      def start!
        install_signal_handlers!
        transition_to(:working)

        loop do
          break if @stop_requested
          break if safety_limit_reached?

          task = TaskClaimer.call(task_manager: @task_manager, agent_name: @agent_name)

          if task
            run_work_phase(task)
            @runs_completed += 1
          else
            result = run_idle_phase
            case result
            when :shutdown, :interrupted
              break
            when :resume
              transition_to(:working)
              next
            end
          end
        end

        shutdown!
      end

      # Requests a graceful shutdown. The daemon will finish its current
      # work unit and then stop.
      #
      # @return [void]
      def stop!
        @stop_requested = true
        @idle_poller&.interrupt!
      end

      # @return [Boolean]
      def running?
        %i[working idle].include?(@state)
      end

      # @return [Hash] snapshot of daemon status
      def status
        {
          agent_name: @agent_name,
          role: @role,
          state: @state,
          runs_completed: @runs_completed,
          total_cost: @total_cost,
          max_runs: @max_runs,
          max_cost: @max_cost,
          stop_requested: @stop_requested
        }
      end

      private

      # ── Signal handling ──────────────────────────────────────────

      def assign_core_attrs(agent_name:, role:, llm_client:, project_root:, task_manager:, mailbox:) # rubocop:disable Metrics/ParameterLists -- mirrors constructor keyword args
        @agent_name   = agent_name
        @role         = role
        @llm_client   = llm_client
        @project_root = File.expand_path(project_root)
        @task_manager = task_manager
        @mailbox      = mailbox
      end

      def assign_limits(max_runs:, max_cost:, poll_interval:, idle_timeout:)
        @max_runs      = max_runs
        @max_cost      = max_cost
        @poll_interval = poll_interval
        @idle_timeout  = idle_timeout
      end

      def assign_callbacks_and_state(on_state_change, on_task_complete, on_task_error)
        @on_state_change  = on_state_change
        @on_task_complete = on_task_complete
        @on_task_error    = on_task_error
        @state            = :spawned
        @runs_completed   = 0
        @total_cost       = 0.0
        @stop_requested   = false
      end

      def install_signal_handlers!
        %w[INT TERM].each do |sig|
          Signal.trap(sig) { stop! }
        end
      rescue ArgumentError
        # Some signals not available on all platforms (e.g. Windows)
      end

      # ── Work phase (full Agent::Loop) ────────────────────────────

      # Executes a full agent loop for a single claimed task — with tools,
      # context management, and budget enforcement.
      #
      # @param task [Tasks::Task]
      # @return [void]
      def run_work_phase(task)
        transition_to(:working)

        agent_loop = build_agent_loop
        result_text = agent_loop.send_message(build_work_prompt(task))

        # Accumulate cost via CostCalculator using actual token counts
        track_cost_from_context_manager(agent_loop)

        # Mark the task as completed with the agent's result.
        @task_manager.complete(task.id, result: result_text)

        # Persist conversation as an audit trail
        persist_session_audit(task, agent_loop)

        @on_task_complete&.call(task, result_text)
      rescue StandardError => e
        handle_task_error(task, e)
      end

      # Builds a fresh Agent::Loop wired with all the real tools.
      # Each task gets its own conversation and context so they don't bleed.
      #
      # @return [Agent::Loop]
      def build_agent_loop
        conversation    = Agent::Conversation.new
        tool_executor   = Tools::Executor.new(project_root: @project_root)
        context_manager = Context::Manager.new
        hook_runner     = Hooks::Runner.new(registry: Hooks::Registry.new)
        stall_detector  = Agent::LoopDetector.new

        # Wire dependencies the executor needs for sub-agents / background
        tool_executor.llm_client = @llm_client
        tool_executor.db = @task_manager.db

        Agent::Loop.new(
          llm_client: @llm_client,
          tool_executor: tool_executor,
          context_manager: context_manager,
          hook_runner: hook_runner,
          conversation: conversation,
          permission_tier: :unrestricted,
          stall_detector: stall_detector,
          project_root: @project_root
        )
      end

      # Computes USD cost from the context manager's token counts using
      # Observability::CostCalculator. The old approach checked for a
      # `total_cost` method that never existed on Context::Manager, so
      # @total_cost was always 0.0 and the max_cost safety limit never fired.
      #
      # @param agent_loop [Agent::Loop]
      # @return [void]
      def track_cost_from_context_manager(agent_loop)
        cm = agent_loop.instance_variable_get(:@context_manager)
        return unless cm

        tokens = extract_token_counts(cm)
        return if tokens.values.all?(&:zero?)

        model = @llm_client.respond_to?(:model) ? @llm_client.model : 'claude-sonnet-4-6'
        @total_cost += Observability::CostCalculator.calculate(model: model, **tokens)
      rescue StandardError
        # Non-critical — cost tracking is best-effort
      end

      # @param context_mgr [Context::Manager]
      # @return [Hash] :input_tokens, :output_tokens
      def extract_token_counts(context_mgr)
        {
          input_tokens: context_mgr.respond_to?(:total_input_tokens) ? context_mgr.total_input_tokens.to_i : 0,
          output_tokens: context_mgr.respond_to?(:total_output_tokens) ? context_mgr.total_output_tokens.to_i : 0
        }
      end

      # Handles a task error with retry backoff. Increments the retry count
      # in the task's metadata. After MAX_TASK_RETRIES, marks the task as
      # failed instead of releasing it back to pending.
      #
      # @param task [Tasks::Task]
      # @param error [StandardError]
      # @return [void]
      def handle_task_error(task, error)
        retry_count = extract_retry_count(task) + 1

        metadata = build_retry_metadata(task, retry_count)
        if retry_count >= MAX_TASK_RETRIES
          @task_manager.update(
            task.id,
            status: 'failed',
            owner: nil,
            result: "Failed after #{retry_count} retries. Last error: #{error.message}",
            metadata: JSON.generate(metadata)
          )
        else
          @task_manager.update(
            task.id,
            status: 'pending',
            owner: nil,
            result: "Error (retry #{retry_count}/#{MAX_TASK_RETRIES}): #{error.message}",
            metadata: JSON.generate(metadata)
          )
        end
        @on_task_error&.call(task, error)
      end

      # @param task [Tasks::Task]
      # @return [Integer]
      def extract_retry_count(task)
        meta = parse_task_metadata(task)
        (meta[:retry_count] || meta['retry_count'] || 0).to_i
      end

      # @param task [Tasks::Task]
      # @param retry_count [Integer]
      # @return [Hash]
      def build_retry_metadata(task, retry_count)
        meta = parse_task_metadata(task)
        meta.merge(retry_count: retry_count)
      end

      # @param task [Tasks::Task]
      # @return [Hash]
      def parse_task_metadata(task)
        raw = task.metadata
        case raw
        when Hash then raw
        when String then JSON.parse(raw, symbolize_names: true)
        else {}
        end
      rescue JSON::ParserError
        {}
      end

      # Persists the agent's conversation as a session audit trail after
      # completing a task, so there's a record of what the daemon did.
      #
      # @param task [Tasks::Task]
      # @param agent_loop [Agent::Loop]
      # @return [void]
      def persist_session_audit(task, agent_loop)
        return unless @session_persistence

        conversation = agent_loop.instance_variable_get(:@conversation)
        return unless conversation.respond_to?(:messages)

        session_id = "daemon-#{@agent_name}-#{task.id}"
        @session_persistence.save_session(
          session_id: session_id,
          project_path: @project_root,
          messages: conversation.messages,
          title: "Daemon: #{task.title}",
          metadata: { agent_name: @agent_name, task_id: task.id, task_title: task.title }
        )
      rescue StandardError
        # Non-critical — audit persistence is best-effort
      end

      # ── Idle phase ───────────────────────────────────────────────

      # Delegates to IdlePoller to wait for new work.
      #
      # @return [:resume, :shutdown, :interrupted]
      def run_idle_phase
        transition_to(:idle)

        @idle_poller = IdlePoller.new(
          mailbox: @mailbox,
          task_manager: @task_manager,
          agent_name: @agent_name,
          poll_interval: @poll_interval,
          idle_timeout: @idle_timeout
        )

        @idle_poller.poll!
      end

      # ── Lifecycle ────────────────────────────────────────────────

      # Performs final shutdown bookkeeping.
      #
      # @return [Symbol] :stopped
      def shutdown!
        transition_to(:shutting_down)
        transition_to(:stopped)
        @state
      end

      # @return [Boolean]
      def safety_limit_reached?
        return true if @runs_completed >= @max_runs
        return true if @total_cost >= @max_cost

        false
      end

      # Transitions the daemon to a new lifecycle state, invoking the
      # optional callback.
      #
      # @param new_state [Symbol]
      # @return [void]
      def transition_to(new_state)
        old_state = @state
        @state = new_state
        @on_state_change&.call(old_state, new_state)
      end

      # ── Prompts ──────────────────────────────────────────────────

      # @param task [Tasks::Task]
      # @return [String]
      def build_work_prompt(task)
        <<~PROMPT
          You are working autonomously as daemon agent "#{@agent_name}".
          Complete the following task using the tools available to you.

          Title: #{task.title}
          Description: #{task.description}
          Priority: #{task.priority}
          Task ID: #{task.id}

          Work in the project at: #{@project_root}
          Be thorough. Use tools to read, write, test, and verify your work.
          When done, summarize what you did.
        PROMPT
      end
    end
  end
end
