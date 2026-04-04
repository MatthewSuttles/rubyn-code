# frozen_string_literal: true

module RubynCode
  module Autonomous
    # Polls for new work when an agent is idle. Checks the mailbox
    # (messages always take priority) and the task board on a regular
    # interval. Blocks the calling thread until work is found, the
    # idle timeout expires, or the poller is interrupted.
    class IdlePoller
      # @param mailbox [#pending_for] message mailbox
      # @param task_manager [#db] task persistence layer
      # @param agent_name [String] the polling agent's identifier
      # @param poll_interval [Numeric] seconds between polls (default 5)
      # @param idle_timeout [Numeric] max seconds to wait before shutdown (default 60)
      def initialize(mailbox:, task_manager:, agent_name:, poll_interval: 5, idle_timeout: 60)
        @mailbox = mailbox
        @task_manager = task_manager
        @agent_name = agent_name
        @poll_interval = poll_interval
        @idle_timeout = idle_timeout
        @interrupted = false
      end

      # Blocks the caller, polling for new work at the configured interval.
      #
      # @return [:resume, :shutdown, :interrupted]
      #   - :resume     - found work (message or task)
      #   - :shutdown   - idle timeout elapsed with no work
      #   - :interrupted - #interrupt! was called externally
      def poll!
        deadline = monotonic_now + @idle_timeout

        loop do
          return :interrupted if @interrupted
          return :shutdown if monotonic_now >= deadline

          # Messages always take priority over tasks.
          return :resume if has_pending_messages?

          return :resume if has_claimable_task?

          remaining = deadline - monotonic_now
          return :shutdown if remaining <= 0

          sleep [remaining, @poll_interval].min
        end
      end

      # Signals the poller to stop at the next iteration.
      #
      # @return [void]
      def interrupt!
        @interrupted = true
      end

      # Re-injects the agent's identity message when the conversation
      # context has been compressed (i.e. the messages array is very short).
      # This ensures the agent still knows who it is after compaction.
      #
      # @param messages [Array<Hash>] the current conversation messages
      # @param identity [String] the identity/system prompt to re-inject
      # @param threshold [Integer] message count below which re-injection triggers (default 3)
      # @return [void]
      def self.reinject_identity(messages, identity:, threshold: 3)
        return if messages.length >= threshold
        return if identity.nil? || identity.empty?

        # Only re-inject if the identity is not already present as the
        # first user message.
        first_user = messages.find { |m| m[:role] == 'user' }
        return if first_user && first_user[:content].to_s.include?(identity[0, 100])

        messages.unshift({ role: 'user', content: identity })
      end

      private

      # @return [Boolean]
      def has_pending_messages?
        messages = @mailbox.pending_for(@agent_name)
        messages.is_a?(Array) ? !messages.empty? : false
      rescue StandardError
        false
      end

      # @return [Boolean]
      def has_claimable_task?
        rows = @task_manager.db.query(<<~SQL).to_a
          SELECT 1 FROM tasks
          WHERE status = 'pending'
            AND (owner IS NULL OR owner = '')
          LIMIT 1
        SQL
        !rows.empty?
      rescue StandardError
        false
      end

      # Monotonic clock to avoid issues with wall-clock adjustments.
      #
      # @return [Float] seconds
      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
