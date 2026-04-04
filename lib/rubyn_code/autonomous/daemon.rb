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
    class Daemon
      LIFECYCLE_STATES = %i[spawned working idle shutting_down stopped].freeze

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
      def initialize( # rubocop:disable Metrics/ParameterLists
        agent_name:, role:, llm_client:, project_root:, task_manager:, mailbox:,
        max_runs: 100, max_cost: 10.0, poll_interval: 5, idle_timeout: 60,
        on_state_change: nil, on_task_complete: nil, on_task_error: nil
      )
        @agent_name      = agent_name
        @role            = role
        @llm_client      = llm_client
        @project_root    = File.expand_path(project_root)
        @task_manager    = task_manager
        @mailbox         = mailbox
        @max_runs        = max_runs
        @max_cost        = max_cost
        @poll_interval   = poll_interval
        @idle_timeout    = idle_timeout
        @on_state_change = on_state_change
        @on_task_complete = on_task_complete
        @on_task_error   = on_task_error

        @state           = :spawned
        @runs_completed  = 0
        @total_cost      = 0.0
        @stop_requested  = false
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

        # Accumulate cost from the budget enforcer
        track_cost_from_enforcer(agent_loop)

        # Mark the task as completed with the agent's result.
        @task_manager.complete(task.id, result: result_text)
        @on_task_complete&.call(task, result_text)
      rescue StandardError => e
        # On failure, release the task so another agent (or retry) can pick it up.
        @task_manager.update(task.id, status: 'pending', owner: nil, result: "Error: #{e.message}")
        @on_task_error&.call(task, e)
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

      # Accumulates cost tracked by the Agent::Loop's context manager.
      #
      # @param agent_loop [Agent::Loop]
      # @return [void]
      def track_cost_from_enforcer(agent_loop)
        # The context manager tracks token usage; we extract cost if available.
        # This is best-effort — the daemon's own total_cost is an approximation.
        cm = agent_loop.instance_variable_get(:@context_manager)
        return unless cm.respond_to?(:total_cost)

        @total_cost += cm.total_cost.to_f
      rescue StandardError
        # Non-critical
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
