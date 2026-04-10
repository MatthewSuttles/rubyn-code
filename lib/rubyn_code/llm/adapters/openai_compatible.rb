# frozen_string_literal: true

module RubynCode
  module LLM
    module Adapters
      # Adapter for OpenAI-compatible providers (Groq, Together, Ollama, etc.).
      #
      # Inherits all OpenAI logic but overrides the base URL, provider name,
      # available models, and API key resolution.
      class OpenAICompatible < OpenAI
        def initialize(provider:, base_url:, api_key: nil, available_models: [])
          super(api_key: api_key, base_url: base_url)
          @provider = provider
          @available_models = available_models.freeze
        end

        def provider_name
          @provider
        end

        def models
          @available_models
        end

        private

        def resolve_api_key
          return @api_key if @api_key

          stored = Auth::TokenStore.load_provider_key(@provider)
          return stored if stored

          env_key = "#{@provider.upcase.tr('-', '_')}_API_KEY"
          ENV.fetch(env_key) do
            return 'no-key-required' if local_provider?

            raise Client::AuthExpiredError,
                  "No #{@provider} API key configured. Set with: /provider set-key #{@provider} <key>"
          end
        end

        def local_provider?
          return false unless @base_url

          @base_url.match?(/localhost|127\.0\.0\.1|0\.0\.0\.0/)
        end
      end
    end
  end
end
