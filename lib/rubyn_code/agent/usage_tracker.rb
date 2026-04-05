# frozen_string_literal: true

module RubynCode
  module Agent
    # Tracks token usage and task budgets from LLM responses.
    # Extracted from ResponseParser to keep module size manageable.
    module UsageTracker
      TASK_BUDGET_TOTAL = 100_000 # tokens per user message

      private

      def track_usage(response)
        usage = extract_usage(response)
        return unless usage

        log_usage(usage)
        @context_manager.track_usage(usage)
      rescue NoMethodError
        # context_manager does not implement track_usage yet
      end

      def extract_usage(response)
        if response.respond_to?(:usage)
          response.usage
        elsif response.is_a?(Hash)
          response[:usage] || response['usage']
        end
      end

      def log_usage(usage)
        input_tokens  = usage.respond_to?(:input_tokens) ? usage.input_tokens : usage[:input_tokens]
        output_tokens = usage.respond_to?(:output_tokens) ? usage.output_tokens : usage[:output_tokens]
        cache_info    = build_cache_info(usage)
        RubynCode::Debug.token("in=#{input_tokens} out=#{output_tokens}#{cache_info}")
      end

      def build_cache_info(usage)
        cache_create = usage.respond_to?(:cache_creation_input_tokens) ? usage.cache_creation_input_tokens.to_i : 0
        cache_read   = usage.respond_to?(:cache_read_input_tokens) ? usage.cache_read_input_tokens.to_i : 0
        return '' unless cache_create.positive? || cache_read.positive?

        " cache_create=#{cache_create} cache_read=#{cache_read}"
      end

      def update_task_budget(response)
        usage = response.respond_to?(:usage) ? response.usage : nil
        return unless usage

        output = usage.respond_to?(:output_tokens) ? usage.output_tokens.to_i : 0
        input  = usage.respond_to?(:input_tokens) ? usage.input_tokens.to_i : 0

        @task_budget_remaining ||= TASK_BUDGET_TOTAL
        @task_budget_remaining = [@task_budget_remaining - input - output, 0].max

        RubynCode::Debug.token("task_budget_remaining=#{@task_budget_remaining}/#{TASK_BUDGET_TOTAL}")
      end
    end
  end
end
