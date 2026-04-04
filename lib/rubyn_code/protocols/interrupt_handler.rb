# frozen_string_literal: true

module RubynCode
  module Protocols
    # Handles SIGINT (Ctrl-C) gracefully with a two-stage interrupt protocol.
    #
    # First Ctrl-C sets the interrupted flag so the current LLM call can
    # check and abort gracefully. A second Ctrl-C within 2 seconds forces
    # an immediate exit.
    module InterruptHandler
      @interrupted = false
      @last_interrupt_at = nil
      @callbacks = []
      @mutex = Mutex.new

      class << self
        # Installs the SIGINT trap with the two-stage interrupt protocol.
        #
        # @return [void]
        def setup!
          @mutex.synchronize do
            @interrupted = false
            @last_interrupt_at = nil
          end

          trap('INT') do
            handle_interrupt
          end
        end

        # Returns whether the interrupted flag is currently set.
        #
        # @return [Boolean]
        def interrupted?
          @mutex.synchronize { @interrupted }
        end

        # Clears the interrupted flag and resets the last interrupt timestamp.
        #
        # @return [void]
        def reset!
          @mutex.synchronize do
            @interrupted = false
            @last_interrupt_at = nil
          end
        end

        # Registers a callback to be invoked on the first interrupt.
        # Callbacks are executed in registration order.
        #
        # @yield the block to run on interrupt
        # @return [void]
        def on_interrupt(&block)
          @mutex.synchronize do
            @callbacks << block
          end
        end

        # Clears all registered callbacks. Intended for test cleanup.
        #
        # @return [void]
        def clear_callbacks!
          @mutex.synchronize { @callbacks.clear }
        end

        private

        # Core interrupt handler logic. Called from the SIGINT trap.
        # Signal handlers must be reentrant-safe and avoid complex operations.
        def handle_interrupt
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          if @last_interrupt_at && (now - @last_interrupt_at) < 2.0
            # Second Ctrl-C within 2 seconds: force exit
            $stderr.write("\nForce exiting...\n")
            exit!(1)
          end

          @last_interrupt_at = now
          @interrupted = true

          $stderr.write("\nInterrupted. Press Ctrl-C again within 2s to force exit.\n")

          # Fire callbacks outside the mutex to avoid deadlock in signal context.
          # We read the callbacks array directly since signal handlers should be fast.
          @callbacks.each do |callback|
            callback.call
          rescue StandardError
            # Swallow errors in signal handlers to avoid crashing
          end
        end
      end
    end
  end
end
