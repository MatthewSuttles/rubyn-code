# frozen_string_literal: true

module RubynCode
  module CLI
    # Drives a repeating execution of a payload (a prompt or slash command).
    #
    # Pure orchestration with injected dependencies so it can be unit-tested
    # without a REPL: the caller supplies a `runner` callable that performs one
    # iteration and a `sleeper` for the wait between iterations.
    #
    # Two modes:
    #   - interval mode (interval is a positive number of seconds): run, wait,
    #     run, ... until max_iterations or stopped.
    #   - self-paced mode (interval is nil): run back-to-back until the runner
    #     returns :stop, emits the DONE_SENTINEL, or max_iterations is hit.
    class LoopRunner
      DEFAULT_MAX_ITERATIONS = 50
      DONE_SENTINEL = 'LOOP_DONE'
      UNITS = { 's' => 1, 'm' => 60, 'h' => 3600 }.freeze

      # Parse an interval token like "30s", "5m", "2h", or a bare "45"
      # (seconds). Returns nil when the token is not a valid interval.
      #
      # @param token [String, nil]
      # @return [Integer, nil] seconds, or nil
      def self.parse_interval(token)
        return nil if token.nil?

        match = token.strip.match(/\A(\d+)\s*([smh]?)\z/i)
        return nil unless match

        amount = match[1].to_i
        return nil if amount <= 0

        amount * UNITS.fetch(match[2].downcase, 1)
      end

      # @param interval [Integer, nil] seconds between runs; nil => self-paced
      # @param runner [#call] ->(iteration_index) => String|:stop
      # @param max_iterations [Integer] hard cap on iterations
      # @param sleeper [#call, nil] ->(seconds); defaults to Kernel#sleep
      # @param on_iteration [#call, nil] ->(n, total) UI callback before each run
      def initialize(runner:, interval: nil, max_iterations: DEFAULT_MAX_ITERATIONS,
                     sleeper: nil, on_iteration: nil)
        @interval = interval
        @runner = runner
        @max_iterations = max_iterations
        @sleeper = sleeper || ->(seconds) { sleep(seconds) }
        @on_iteration = on_iteration
        @stopped = false
      end

      # Request the loop to stop after the current iteration.
      # @return [void]
      def stop!
        @stopped = true
      end

      # @return [Boolean]
      def stopped? = @stopped

      # Run the loop.
      #
      # @return [Integer] number of iterations completed
      def run
        completed = 0
        @max_iterations.times do |index|
          break if @stopped

          @on_iteration&.call(index + 1, @max_iterations)
          result = @runner.call(index)
          completed += 1

          break if @stopped || done?(result)

          wait_before_next(index)
        end
        completed
      rescue Interrupt
        completed
      end

      private

      def wait_before_next(index)
        return unless @interval && index < @max_iterations - 1

        @sleeper.call(@interval)
      end

      def done?(result)
        return true if result == :stop

        result.is_a?(String) && result.include?(DONE_SENTINEL)
      end
    end
  end
end
