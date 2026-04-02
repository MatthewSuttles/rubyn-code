# frozen_string_literal: true

require "monitor"

module RubynCode
  module Hooks
    # Thread-safe registry for hook callables keyed by event type.
    #
    # Hooks can be registered as blocks or any object responding to #call.
    # Each hook is stored with an optional priority (lower runs first).
    class Registry
      VALID_EVENTS = %i[
        pre_tool_use
        post_tool_use
        pre_llm_call
        post_llm_call
        on_stall
        on_error
        on_session_end
      ].freeze

      Hook = Data.define(:callable, :priority)

      include MonitorMixin

      def initialize
        super() # MonitorMixin
        @hooks = {}
        VALID_EVENTS.each { |event| @hooks[event] = [] }
      end

      # Registers a hook for the given event.
      #
      # @param event [Symbol] one of VALID_EVENTS
      # @param callable [#call, nil] an object responding to #call, or nil if a block is given
      # @param priority [Integer] execution order (lower runs first, default 100)
      # @yield the hook block (used when callable is nil)
      # @return [void]
      def on(event, callable = nil, priority: 100, &block)
        event = event.to_sym
        validate_event!(event)

        handler = callable || block
        raise ArgumentError, "A callable or block is required" unless handler
        raise ArgumentError, "Hook must respond to #call" unless handler.respond_to?(:call)

        synchronize do
          @hooks[event] << Hook.new(callable: handler, priority: priority)
          @hooks[event].sort_by!(&:priority)
        end
      end

      # Returns an array of callables registered for the given event,
      # ordered by priority (lowest first).
      #
      # @param event [Symbol]
      # @return [Array<#call>]
      def hooks_for(event)
        event = event.to_sym
        synchronize do
          (@hooks[event] || []).map(&:callable)
        end
      end

      # Clears hooks for a specific event, or all hooks if no event is given.
      #
      # @param event [Symbol, nil]
      # @return [void]
      def clear!(event = nil)
        synchronize do
          if event
            event = event.to_sym
            @hooks[event] = [] if @hooks.key?(event)
          else
            @hooks.each_key { |e| @hooks[e] = [] }
          end
        end
      end

      # Returns a list of event types that have at least one hook registered.
      #
      # @return [Array<Symbol>]
      def registered_events
        synchronize do
          @hooks.select { |_, hooks| hooks.any? }.keys
        end
      end

      private

      def validate_event!(event)
        return if VALID_EVENTS.include?(event)

        raise ArgumentError,
              "Unknown event #{event.inspect}. Valid events: #{VALID_EVENTS.join(", ")}"
      end
    end
  end
end
