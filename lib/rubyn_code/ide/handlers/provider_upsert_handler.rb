# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Adds or updates an OpenAI/Anthropic-compatible provider for IDE hosts.
      # API keys are handed directly to TokenStore and never echoed over RPC.
      class ProviderUpsertHandler
        FORMATS = %w[openai anthropic].freeze

        def initialize(server)
          @server = server
        end

        def call(params)
          provider = normalized_provider(params)
          error = validate(**provider)
          return { 'updated' => false, 'error' => error } if error

          persist_provider(provider, params)
          @server.notify('config/changed', { 'key' => 'providers', 'provider' => provider[:name] })
          { 'updated' => true, 'provider' => provider_payload(provider, params) }
        rescue Config::Settings::LoadError, Auth::ProviderKeychain::CredentialStoreError => e
          { 'updated' => false, 'error' => e.message }
        end

        private

        def normalized_provider(params)
          {
            name: params['name'].to_s.strip.downcase,
            base_url: params['baseUrl'].to_s.strip.sub(%r{/+\z}, ''),
            models: Array(params['models']).map { |model| model.to_s.strip }.reject(&:empty?).uniq,
            api_format: params.fetch('apiFormat', 'openai').to_s
          }
        end

        def persist_provider(provider, params)
          Config::Settings.new.add_provider(
            provider[:name],
            base_url: provider[:base_url],
            env_key: params['envKey'].to_s.strip.empty? ? nil : params['envKey'].to_s.strip,
            models: provider[:models],
            api_format: provider[:api_format]
          )
          key = params['apiKey'].to_s
          Auth::TokenStore.save_provider_key(provider[:name], key) unless key.empty?
        end

        def validate(name:, base_url:, models:, api_format:)
          unless name.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
            return 'Provider name must use letters, numbers, dashes, or underscores'
          end
          return 'Base URL must be an http:// or https:// URL' unless base_url.match?(%r{\Ahttps?://[^\s]+\z})
          return 'Add at least one model' if models.empty?

          "API format must be one of: #{FORMATS.join(', ')}" unless FORMATS.include?(api_format)
        end

        def provider_payload(provider, params)
          {
            'name' => provider[:name],
            'baseUrl' => provider[:base_url],
            'apiFormat' => provider[:api_format],
            'envKey' => params['envKey'].to_s.strip,
            'models' => provider[:models]
          }
        end
      end
    end
  end
end
