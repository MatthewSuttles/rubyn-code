# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'json'
require 'time'
require_relative 'token_result'
require_relative 'strategies/base'
require_relative 'strategies/keychain'
require_relative 'strategies/credentials_file'
require_relative 'strategies/local_file'
require_relative 'strategies/env_var'

module RubynCode
  module Auth
    module TokenStore
      EXPIRY_BUFFER_SECONDS = 300 # 5 minutes

      # Providers with custom strategy chains (e.g., OAuth with refresh tokens).
      # All other providers fall back to DEFAULT_STRATEGIES.
      CUSTOM_STRATEGIES = {
        'anthropic' => [
          Strategies::Keychain,
          Strategies::CredentialsFile,
          Strategies::LocalFile,
          Strategies::EnvVar
        ]
      }.freeze

      # Default strategy chain for providers without custom configuration.
      DEFAULT_STRATEGIES = [Strategies::EnvVar].freeze

      class << self
        # Load API key for a given provider using its strategy chain.
        #
        # Each provider has a strategy chain defined in CUSTOM_STRATEGIES,
        # or falls back to DEFAULT_STRATEGIES (EnvVar only).
        #
        # @param provider [String] provider name (e.g., 'anthropic', 'openai')
        # @return [Hash, nil] token hash or nil if no token found
        def load_for_provider(provider)
          strategies = CUSTOM_STRATEGIES.fetch(provider, DEFAULT_STRATEGIES)

          strategies.each do |strategy_class|
            result = instantiate_and_call(strategy_class, provider)
            return result.to_h if result
          end

          nil
        end

        # Get the environment variable key for a given provider.
        # Reads from Config::Defaults::PROVIDER_ENV_KEYS (single source of truth).
        #
        # @param provider [String] provider name
        # @return [String, nil] env key name or nil if not defined
        def env_key_for(provider)
          Config::Defaults::PROVIDER_ENV_KEYS.fetch(provider, nil)
        end

        def save(access_token:, refresh_token:, expires_at:)
          ensure_directory!

          data = {
            'access_token' => access_token,
            'refresh_token' => refresh_token,
            'expires_at' => expires_at.is_a?(Time) ? expires_at.iso8601 : expires_at.to_s
          }

          File.write(tokens_path, YAML.dump(data))
          File.chmod(0o600, tokens_path)
          data
        end

        def clear! # rubocop:disable Naming/PredicateMethod -- destructive action, not a predicate
          FileUtils.rm_f(tokens_path)
          true
        end

        # Check if valid credentials exist for a given provider.
        #
        # @param provider [String] provider name
        # @return [Boolean]
        def valid_for?(provider)
          tokens = load_for_provider(provider)
          return false unless tokens&.fetch(:access_token, nil)
          return true if tokens[:type] == :api_key
          return true unless tokens[:expires_at]

          tokens[:expires_at] > Time.now + EXPIRY_BUFFER_SECONDS
        end

        # Check if any credentials exist for a given provider (valid or not).
        #
        # @param provider [String] provider name
        # @return [Boolean]
        def exists_for?(provider) = valid_for?(provider)

        # Get just the access token for a given provider.
        #
        # @param provider [String] provider name
        # @return [String, nil]
        def access_token_for(provider) = load_for_provider(provider)&.fetch(:access_token, nil)

        # Get the human-readable display name for a token source.
        #
        # @param source [Symbol] the source identifier (e.g., :keychain, :env)
        # @return [String, nil] display name or nil if source not found
        def display_name_for(source)
          strategy_class = find_strategy_by_source(source)
          strategy_class&.display_name
        end

        # Get setup hints for all strategies in a provider's chain.
        # Returns only non-nil hints (e.g., platform-specific ones).
        #
        # @param provider [String] provider name (e.g., 'anthropic')
        # @return [Array<String>] list of setup hints
        def setup_hints_for(provider)
          strategies = CUSTOM_STRATEGIES.fetch(provider, DEFAULT_STRATEGIES)

          strategies.map do |strategy_class|
            hint_for_strategy(strategy_class, provider)
          end.compact
        end

        private

        def hint_for_strategy(strategy_class, provider)
          if strategy_class == Strategies::EnvVar
            env_key = env_key_for(provider) || "#{provider.upcase}_API_KEY"
            "Set #{env_key} environment variable"
          else
            strategy_class.setup_hint
          end
        end

        def find_strategy_by_source(source)
          all_strategies = CUSTOM_STRATEGIES.values.flatten + DEFAULT_STRATEGIES
          all_strategies.uniq.find do |klass|
            source == klass::SOURCE
          end
        end

        def instantiate_and_call(strategy_class, provider)
          if strategy_class == Strategies::EnvVar
            strategy_class.new(provider).call
          else
            strategy_class.new.call
          end
        end

        def tokens_path = Config::Defaults::TOKENS_FILE

        def ensure_directory!
          FileUtils.mkdir_p(File.dirname(tokens_path))
          File.chmod(0o700, File.dirname(tokens_path))
        end
      end
    end
  end
end
