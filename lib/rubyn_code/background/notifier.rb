# frozen_string_literal: true

module RubynCode
  module Background
    # Thread-safe notification queue for background job completions.
    # Uses Ruby's stdlib Queue which is already thread-safe for push/pop,
    # but we guard drain with a mutex to prevent interleaved partial drains.
    class Notifier
      def initialize
        @queue = Queue.new
        @drain_mutex = Mutex.new
      end

      # Enqueues a notification.
      #
      # @param notification [Hash, String, Object] arbitrary notification payload
      # @return [void]
      def push(notification)
        @queue.push(notification)
      end

      # Drains all pending notifications in a single atomic operation.
      # Returns an empty array if nothing is pending.
      #
      # @return [Array] all pending notifications
      def drain
        @drain_mutex.synchronize do
          notifications = []
          notifications << @queue.pop until @queue.empty?
          notifications
        end
      end

      # Returns true if there are notifications waiting.
      #
      # @return [Boolean]
      def pending?
        !@queue.empty?
      end
    end
  end
end
