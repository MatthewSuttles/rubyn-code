# frozen_string_literal: true

module RubynCode
  module Hooks
    # Executes registered hooks for a given event in priority order.
    #
    # Hook execution is defensive: exceptions raised by individual hooks are
    # caught and logged rather than allowed to crash the agent. Special
    # semantics apply to :pre_tool_use (deny gating) and :post_tool_use
    # (output transformation).
    #
    # The runner can also fan out to an external hook dispatcher (see
    # ExternalDispatcher) which spawns Claude Code-style hook commands
    # configured in settings.json. External hooks participate in the same
    # deny/block decisions as in-process hooks.
    class Runner
      # @param registry [Hooks::Registry] the hook registry to draw from
      # @param external_dispatcher [Hooks::ExternalDispatcher, nil] optional
      #   dispatcher for Claude Code-style external hook commands
      def initialize(registry: Registry.new, external_dispatcher: nil)
        @registry = registry
        @external_dispatcher = external_dispatcher
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
        external_response = fire_external(event, **context)

        case event
        when :pre_tool_use
          merge_pre_tool_use(fire_pre_tool_use(hooks, context), external_response)
        when :post_tool_use
          # External hooks contribute additionalContext (read by the LLM
          # caller) but do not transform tool output — that's a job for
          # in-process hooks only.
          fire_post_tool_use(hooks, context)
        when :stop
          merge_stop(fire_stop(hooks, context), external_response)
        else
          fire_generic(hooks, event, context)
          external_response&.additional_context
        end
      end

      private

      # @return [Hooks::Response, nil] nil when no external dispatcher or
      #   no hooks are configured for this event.
      def fire_external(event, **context)
        return nil unless @external_dispatcher

        @external_dispatcher.fire(event, **context)
      rescue StandardError => e
        warn "[RubynCode::Hooks] External dispatcher error during #{event}: #{e.class}: #{e.message}"
        nil
      end

      # In-process deny takes precedence over external block. Either way,
      # if any source denies, return a deny hash.
      def merge_pre_tool_use(in_process_result, external_response)
        return in_process_result if in_process_result.is_a?(Hash) && in_process_result[:deny]

        return nil unless external_response&.block?

        { deny: true, reason: external_response.reason || 'Blocked by external hook' }
      end

      # Same precedence for stop: in-process block wins; external stop otherwise.
      def merge_stop(in_process_result, external_response)
        return in_process_result if in_process_result.is_a?(Hash) && in_process_result[:block]

        return nil unless external_response&.stop?

        { block: true, reason: external_response.stop_reason || 'Stopped by external hook' }
      end

      # For :stop, if any hook returns a hash with { block: true }, execution
      # stops and the block result is returned — signalling the agent loop to
      # keep working instead of finalizing (e.g. an active /goal).
      def fire_stop(hooks, context)
        hooks.each do |hook|
          result = safe_call(hook, :stop, context)
          next unless result.is_a?(Hash) && result[:block]

          return { block: true, reason: result[:reason] || 'Stop blocked by hook' }
        end

        nil
      end

      # For :pre_tool_use, if any hook returns a hash with { deny: true },
      # execution stops and the deny result is returned immediately.
      def fire_pre_tool_use(hooks, context)
        hooks.each do |hook|
          result = safe_call(hook, :pre_tool_use, context)
          next unless result.is_a?(Hash) && result[:deny]

          return { deny: true, reason: result[:reason] || 'Denied by hook' }
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
