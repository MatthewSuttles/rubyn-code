# frozen_string_literal: true

require_relative 'base'

module RubynCode
  module Auth
    module Strategies
      # Reads an API key from an environment variable. Works for any provider:
      # the env key is resolved from Config::Defaults::PROVIDER_ENV_KEYS or
      # from the provider's config.yml entry, falling back to a conventional
      # "#{PROVIDER}_API_KEY" name.
      class EnvVar < Base
        SOURCE = :env

        def self.display_name = 'environment variable'

        def self.setup_hint
          'Set ANTHROPIC_API_KEY environment variable'
        end

        # @param provider [String] the provider name (e.g., 'anthropic', 'openai')
        def initialize(provider)
          super()
          @provider = provider
        end

        # @return [TokenResult, nil]
        def call
          env_key = resolve_env_key
          api_key = ENV.fetch(env_key, nil)
          return nil if api_key.nil? || api_key.empty?

          build_result(
            access_token: api_key,
            refresh_token: nil,
            expires_at: nil,
            type: :api_key,
            source: SOURCE
          )
        end

        private

        def resolve_env_key
          # 1. Check TokenStore's PROVIDER_STRATEGIES
          from_token_store = RubynCode::Auth::TokenStore.env_key_for(@provider)
          return from_token_store if from_token_store

          # 2. Fall back to Config::Defaults
          default = Config::Defaults::PROVIDER_ENV_KEYS.fetch(@provider, "#{@provider.upcase}_API_KEY")

          # 3. Allow override via config.yml
          Config::Settings.new.provider_config(@provider)&.fetch('env_key', nil) || default
        rescue StandardError
          "#{@provider.upcase}_API_KEY"
        end
      end
    end
  end
end
