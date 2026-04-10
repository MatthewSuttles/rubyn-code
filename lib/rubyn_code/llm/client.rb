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
        settings = Config::Settings.new
        @model = model || settings.model
        @provider = provider || settings.provider
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

      def build_custom_adapter(provider, config, base_url, available_models)
        case config.fetch('api_format', 'openai')
        when 'anthropic'
          Adapters::AnthropicCompatible.new(provider: provider, base_url: base_url, available_models: available_models)
        else
          Adapters::OpenAICompatible.new(provider: provider, base_url: base_url, available_models: available_models)
        end
      end

      def extract_model_names(config)
        raw = config&.dig('models')
        return [] unless raw

        raw.is_a?(Hash) ? raw.values : Array(raw)
      end

      # Builds the appropriate adapter for a given provider name.
      def resolve_adapter(provider)
        case provider
        when 'anthropic' then Adapters::Anthropic.new
        when 'openai' then Adapters::OpenAI.new
        else
          config = Config::Settings.new.provider_config(provider)
          base_url = config&.fetch('base_url', nil)

          if config.nil?
            raise ConfigError,
                  "Unknown provider '#{provider}'. " \
                  "Add it to config.yml under providers.#{provider} with base_url, env_key, and models."
          end

          unless base_url
            raise ConfigError,
                  "Provider '#{provider}' is missing base_url in config.yml. " \
                  "Add base_url under providers.#{provider} (e.g., base_url: https://api.#{provider}.com/v1)"
          end

          available_models = extract_model_names(config)
          build_custom_adapter(provider, config, base_url, available_models)
        end
      end
    end
  end
end
