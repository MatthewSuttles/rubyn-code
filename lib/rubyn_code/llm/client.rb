# frozen_string_literal: true

require_relative 'message_builder'

module RubynCode
  module LLM
    # Thin facade over provider-specific adapters.
    #
    # All consumers (Agent::Loop, REPL, DaemonRunner) talk to Client.
    # Client delegates to the resolved adapter (currently Anthropic only).
    # This keeps the adapter swap invisible to the rest of the codebase.
    class Client
      class RequestError < RubynCode::Error; end
      class AuthExpiredError < RubynCode::AuthenticationError; end
      class PromptTooLongError < RequestError; end

      attr_reader :adapter

      def initialize(model: nil, adapter: nil)
        @model = model || Config::Defaults::DEFAULT_MODEL
        @adapter = adapter || default_adapter
      end

      def chat(messages:, tools: nil, system: nil, model: nil, **opts)
        effective_model = model || @model
        max_tokens = opts[:max_tokens] || Config::Defaults::CAPPED_MAX_OUTPUT_TOKENS

        @adapter.chat(
          messages: messages,
          tools: tools,
          system: system,
          model: effective_model,
          max_tokens: max_tokens,
          on_text: opts[:on_text],
          task_budget: opts[:task_budget]
        )
      end

      def stream(messages:, tools: nil, system: nil, model: nil,
                 max_tokens: Config::Defaults::CAPPED_MAX_OUTPUT_TOKENS, &block)
        chat(messages: messages, tools: tools, system: system,
             model: model, max_tokens: max_tokens, on_text: block)
      end

      def provider_name
        @adapter.provider_name
      end

      def models
        @adapter.models
      end

      private

      def default_adapter
        Adapters::Anthropic.new
      end
    end
  end
end
