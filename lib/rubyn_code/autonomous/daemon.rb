# frozen_string_literal: true

require "securerandom"

module RubynCode
  module Autonomous
    # The KAIROS daemon -- an always-on autonomous agent that cycles between
    # working on tasks and polling for new work. The lifecycle is:
    #
    #   spawn -> work -> idle -> work -> ... -> shutdown
    #
    # Safety limits (max_runs, max_cost) prevent runaway execution.
    class Daemon
      LIFECYCLE_STATES = %i[spawned working idle shutting_down stopped].freeze

      attr_reader :agent_name, :role, :state, :runs_completed, :total_cost

      # @param agent_name [String] unique name for this daemon instance
      # @param role [String] the agent's role / persona description
      # @param llm_client [LLM::Client] LLM API client
      # @param project_root [String] path to the project being worked on
      # @param task_manager [#db] task persistence layer
      # @param mailbox [#pending_for] message mailbox
      # @param max_runs [Integer] maximum work cycles before auto-shutdown (default 100)
      # @param max_cost [Float] maximum cumulative LLM cost in USD before auto-shutdown (default 10.0)
      # @param poll_interval [Numeric] idle polling interval in seconds (default 5)
      # @param idle_timeout [Numeric] seconds of idle before shutdown (default 60)
      # @param on_state_change [Proc, nil] callback invoked with (old_state, new_state)
      def initialize(agent_name:, role:, llm_client:, project_root:, task_manager:, mailbox:, # rubocop:disable Metrics/ParameterLists
                     max_runs: 100, max_cost: 10.0, poll_interval: 5, idle_timeout: 60,
                     on_state_change: nil)
        @agent_name = agent_name
        @role = role
        @llm_client = llm_client
        @project_root = File.expand_path(project_root)
        @task_manager = task_manager
        @mailbox = mailbox
        @max_runs = max_runs
        @max_cost = max_cost
        @poll_interval = poll_interval
        @idle_timeout = idle_timeout
        @on_state_change = on_state_change

        @state = :spawned
        @runs_completed = 0
        @total_cost = 0.0
        @stop_requested = false
      end

      # Enters the work-idle-work cycle. Blocks the calling thread until
      # the daemon shuts down (via safety limits, idle timeout, or #stop!).
      #
      # @return [Symbol] the final state (:stopped)
      def start!
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

      # Executes the agent loop for a single claimed task.
      #
      # @param task [Tasks::Task]
      # @return [void]
      def run_work_phase(task)
        transition_to(:working)

        conversation = Agent::Conversation.new
        conversation.add_user_message(build_work_prompt(task))

        response = @llm_client.chat(
          messages: conversation.to_api_format,
          system: build_system_prompt
        )

        track_cost(response)

        # Mark the task as completed with the agent's result.
        result_text = extract_result(response)
        @task_manager.db.execute(
          "UPDATE tasks SET status = 'completed', result = ?, updated_at = datetime('now') WHERE id = ?",
          [result_text, task.id]
        )
      rescue StandardError => e
        # On failure, release the task so another agent (or retry) can pick it up.
        @task_manager.db.execute(
          "UPDATE tasks SET status = 'pending', owner = NULL, result = ?, updated_at = datetime('now') WHERE id = ?",
          ["Error: #{e.message}", task.id]
        )
      end

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

      # Accumulates cost from an LLM response.
      #
      # @param response [#usage] LLM response with usage data
      # @return [void]
      def track_cost(response)
        return unless response.respond_to?(:usage) && response.usage.respond_to?(:cost)

        @total_cost += response.usage.cost.to_f
      end

      # Extracts the textual result from an LLM response.
      #
      # @param response [#content] LLM response
      # @return [String]
      def extract_result(response)
        return "" unless response.respond_to?(:content)

        case response.content
        when String
          response.content
        when Array
          text_blocks = response.content.select { |b| b.is_a?(Hash) && b[:type] == "text" }
          text_blocks.map { |b| b[:text] }.join("\n")
        else
          response.content.to_s
        end
      end

      # @param task [Tasks::Task]
      # @return [String]
      def build_work_prompt(task)
        "Execute the following task:\n\n" \
          "Title: #{task.title}\n" \
          "Description: #{task.description}\n" \
          "Priority: #{task.priority}\n" \
          "Task ID: #{task.id}"
      end

      # @return [String]
      def build_system_prompt
        "You are #{@agent_name}, an autonomous agent with the role: #{@role}. " \
          "You are working on the project at #{@project_root}. " \
          "Complete tasks thoroughly and report results clearly."
      end
    end
  end
end
