# frozen_string_literal: true

module RubynCode
  module Hooks
    # Executes registered hooks for a given event in priority order.
    #
    # Hook execution is defensive: exceptions raised by individual hooks are
    # caught and logged rather than allowed to crash the agent. Special
    # semantics apply to :pre_tool_use (deny gating) and :post_tool_use
    # (output transformation).
    class Runner
      # @param registry [Hooks::Registry] the hook registry to draw from
      def initialize(registry: Registry.new)
        @registry = registry
      end

      # Fires all hooks for the given event with the supplied context.
      #
      # @param event [Symbol] the event type
      # @param context [Hash] keyword arguments passed to each hook
      # @return [Hash, Object, nil] depends on event semantics:
      #   - :pre_tool_use => { deny: true, reason: "..." } if any hook denies, else nil
      #   - :post_tool_use => the (possibly transformed) output
      #   - all others => nil
      def fire(event, **context)
        hooks = @registry.hooks_for(event)
        return if hooks.empty?

        case event
        when :pre_tool_use
          fire_pre_tool_use(hooks, context)
        when :post_tool_use
          fire_post_tool_use(hooks, context)
        else
          fire_generic(hooks, event, context)
        end
      end

      private

      # For :pre_tool_use, if any hook returns a hash with { deny: true },
      # execution stops and the deny result is returned immediately.
      def fire_pre_tool_use(hooks, context)
        hooks.each do |hook|
          result = safe_call(hook, :pre_tool_use, context)
          next unless result.is_a?(Hash) && result[:deny]

          return { deny: true, reason: result[:reason] || "Denied by hook" }
        end

        nil
      end

      # For :post_tool_use, each hook receives the output from the previous
      # hook (or the original result). This allows hooks to transform output
      # in a pipeline fashion.
      def fire_post_tool_use(hooks, context)
        output = context[:result]

        hooks.each do |hook|
          transformed = safe_call(hook, :post_tool_use, context.merge(result: output))
          output = transformed unless transformed.nil?
        end

        output
      end

      # Generic hook execution: run all hooks, ignore return values.
      def fire_generic(hooks, event, context)
        hooks.each { |hook| safe_call(hook, event, context) }
        nil
      end

      # Calls a hook safely, catching and logging any exceptions.
      #
      # @param hook [#call] the hook callable
      # @param event [Symbol] the event (for error reporting)
      # @param context [Hash] the context to pass
      # @return [Object, nil] the hook's return value, or nil on error
      def safe_call(hook, event, context)
        hook.call(**context)
      rescue StandardError => e
        warn "[RubynCode::Hooks] Hook error during #{event}: #{e.class}: #{e.message}"
        nil
      end
    end
  end
end
