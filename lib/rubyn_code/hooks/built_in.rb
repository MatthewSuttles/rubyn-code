# frozen_string_literal: true

module RubynCode
  module Hooks
    # Default hooks shipped with rubyn-code. These provide core functionality
    # such as cost tracking, tool-call logging, and automatic context compaction.
    module BuiltIn
      # Records cost data after each LLM call using the BudgetEnforcer.
      #
      # Expects the :post_llm_call context to include:
      #   - response: the raw API response hash (with :usage or "usage" key)
      #   - budget_enforcer: an Observability::BudgetEnforcer instance (optional)
      class CostTrackingHook
        # @param budget_enforcer [Observability::BudgetEnforcer]
        def initialize(budget_enforcer:)
          @budget_enforcer = budget_enforcer
        end

        # @param response [Hash] the LLM API response
        # @param kwargs [Hash] remaining context (ignored)
        # @return [void]
        def call(response:, **_kwargs)
          return unless @budget_enforcer

          usage = response[:usage] || response["usage"]
          return unless usage

          model          = response[:model] || response["model"] || "unknown"
          input_tokens   = usage[:input_tokens] || usage["input_tokens"] || 0
          output_tokens  = usage[:output_tokens] || usage["output_tokens"] || 0
          cache_read     = usage[:cache_read_input_tokens] || usage["cache_read_input_tokens"] || 0
          cache_write    = usage[:cache_creation_input_tokens] || usage["cache_creation_input_tokens"] || 0

          @budget_enforcer.record!(
            model: model,
            input_tokens: input_tokens,
            output_tokens: output_tokens,
            cache_read_tokens: cache_read,
            cache_write_tokens: cache_write
          )
        end
      end

      # Logs tool calls and their results via the formatter.
      #
      # Listens to :pre_tool_use and :post_tool_use events.
      class LoggingHook
        # @param formatter [Output::Formatter]
        def initialize(formatter:)
          @formatter = formatter
        end

        # Handles both :pre_tool_use and :post_tool_use events.
        #
        # For :pre_tool_use, logs the tool name and input arguments.
        # For :post_tool_use, logs the tool result.
        #
        # @param tool_name [String] name of the tool
        # @param tool_input [Hash] input arguments (for pre_tool_use)
        # @param result [String, nil] tool output (for post_tool_use)
        # @param kwargs [Hash] remaining context
        # @return [nil]
        def call(tool_name:, tool_input: {}, result: nil, **_kwargs)
          if result.nil?
            @formatter.tool_call(tool_name, tool_input)
          else
            @formatter.tool_result(tool_name, result, success: true)
          end

          nil
        end
      end

      # Triggers a compaction check after each LLM call to keep the context
      # window within bounds.
      #
      # Expects the :post_llm_call context to include:
      #   - conversation: the Agent::Conversation instance
      #   - context_manager: a Context::Manager instance (optional)
      class AutoCompactHook
        # @param context_manager [Context::Manager]
        def initialize(context_manager:)
          @context_manager = context_manager
        end

        # @param conversation [Agent::Conversation] the current conversation
        # @param kwargs [Hash] remaining context (ignored)
        # @return [void]
        def call(conversation: nil, **_kwargs)
          return unless @context_manager && conversation

          @context_manager.auto_compact(conversation)
        rescue NoMethodError
          # auto_compact not yet available on this context manager
        end
      end

      class << self
        # Registers all built-in hooks on the given registry.
        #
        # @param registry [Hooks::Registry]
        # @param budget_enforcer [Observability::BudgetEnforcer, nil]
        # @param formatter [Output::Formatter, nil]
        # @param context_manager [Context::Manager, nil]
        # @return [void]
        def register_all!(registry, budget_enforcer: nil, formatter: nil, context_manager: nil)
          if budget_enforcer
            registry.on(:post_llm_call, CostTrackingHook.new(budget_enforcer: budget_enforcer), priority: 10)
          end

          if formatter
            logging_hook = LoggingHook.new(formatter: formatter)
            registry.on(:pre_tool_use,  logging_hook, priority: 50)
            registry.on(:post_tool_use, logging_hook, priority: 50)
          end

          if context_manager
            registry.on(:post_llm_call, AutoCompactHook.new(context_manager: context_manager), priority: 90)
          end
        end
      end
    end
  end
end
