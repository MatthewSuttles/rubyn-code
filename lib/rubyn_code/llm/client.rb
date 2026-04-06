# frozen_string_literal: true

require_relative 'message_builder'

module RubynCode
  module LLM
    # Thin facade over provider-specific adapters.
    #
    # All consumers (Agent::Loop, REPL, DaemonRunner) talk to Client.
    # Client delegates to the resolved adapter, which can be swapped
    # at runtime via `switch_provider!` or the `/model` command.
    class Client
      class RequestError < RubynCode::Error; end
      class AuthExpiredError < RubynCode::AuthenticationError; end
      class PromptTooLongError < RequestError; end

      attr_reader :adapter
      attr_accessor :model

      def initialize(model: nil, provider: nil, adapter: nil)
        @model = model || Config::Defaults::DEFAULT_MODEL
        @provider = provider || Config::Defaults::DEFAULT_PROVIDER
        @adapter = adapter || resolve_adapter(@provider)
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

      # Switch the active provider (and optionally model) at runtime.
      # Called by the REPL when `/model provider:model` is used.
      #
      # @param provider [String] provider name ('anthropic', 'openai', etc.)
      # @param model [String, nil] optional model to set
      def switch_provider!(provider, model: nil)
        @provider = provider
        @adapter = resolve_adapter(provider)
        @model = model if model
      end

      private

      # Builds the appropriate adapter for a given provider name.
      def resolve_adapter(provider)
        case provider
        when 'anthropic' then Adapters::Anthropic.new
        when 'openai' then Adapters::OpenAI.new
        else
          config = Config::Settings.new.provider_config(provider)
          base_url = config&.fetch('base_url', nil)

          unless base_url
            raise ConfigError,
                  "Unknown provider '#{provider}'. Add base_url to config.yml under providers.#{provider}"
          end

          Adapters::OpenAICompatible.new(provider: provider, base_url: base_url)
        end
      end
    end
  end
end
