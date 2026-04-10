# frozen_string_literal: true

module RubynCode
  module LLM
    module Adapters
      # Adapter for Anthropic-compatible providers that use the Messages API format.
      #
      # Inherits all Anthropic logic but overrides the base URL, provider name,
      # available models, and API key resolution.
      class AnthropicCompatible < Anthropic
        def initialize(provider:, base_url:, api_key: nil, available_models: [])
          super()
          @provider = provider
          @base_url = base_url
          @api_key = api_key
          @available_models = available_models.freeze
        end

        def provider_name
          @provider
        end

        def models
          @available_models
        end

        private

        def api_url
          "#{@base_url}/messages"
        end

        def ensure_valid_token!
          resolve_api_key # raises if missing
        end

        def oauth_token?
          false
        end

        def access_token
          resolve_api_key
        end

        def resolve_api_key
          return @api_key if @api_key

          stored = Auth::TokenStore.load_provider_key(@provider)
          return stored if stored

          env_key = "#{@provider.upcase.tr('-', '_')}_API_KEY"
          ENV.fetch(env_key) do
            raise Client::AuthExpiredError,
                  "No #{@provider} API key configured. Set with: /provider set-key #{@provider} <key>"
          end
        end
      end
    end
  end
end
