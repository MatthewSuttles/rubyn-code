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
          name = params['name'].to_s.strip.downcase
          base_url = params['baseUrl'].to_s.strip.sub(%r{/+\z}, '')
          models = Array(params['models']).map { |model| model.to_s.strip }.reject(&:empty?).uniq
          api_format = params.fetch('apiFormat', 'openai').to_s

          error = validate(name, base_url, models, api_format)
          return { 'updated' => false, 'error' => error } if error

          Config::Settings.new.add_provider(
            name,
            base_url: base_url,
            env_key: params['envKey'].to_s.strip.empty? ? nil : params['envKey'].to_s.strip,
            models: models,
            api_format: api_format
          )
          key = params['apiKey'].to_s
          Auth::TokenStore.save_provider_key(name, key) unless key.empty?

          @server.notify('config/changed', { 'key' => 'providers', 'provider' => name })
          { 'updated' => true, 'provider' => provider_payload(name, base_url, models, api_format, params) }
        rescue Config::Settings::LoadError => e
          { 'updated' => false, 'error' => e.message }
        end

        private

        def validate(name, base_url, models, api_format)
          unless name.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
            return 'Provider name must use letters, numbers, dashes, or underscores'
          end
          return 'Base URL must be an http:// or https:// URL' unless base_url.match?(%r{\Ahttps?://[^\s]+\z})
          return 'Add at least one model' if models.empty?
          return "API format must be one of: #{FORMATS.join(', ')}" unless FORMATS.include?(api_format)
        end

        def provider_payload(name, base_url, models, api_format, params)
          {
            'name' => name,
            'baseUrl' => base_url,
            'apiFormat' => api_format,
            'envKey' => params['envKey'].to_s.strip,
            'models' => models
          }
        end
      end
    end
  end
end
