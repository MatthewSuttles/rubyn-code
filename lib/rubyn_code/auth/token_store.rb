# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'json'
require 'time'

module RubynCode
  module Auth
    module TokenStore
      EXPIRY_BUFFER_SECONDS = 300 # 5 minutes
      KEYCHAIN_SERVICE = 'Claude Code-credentials'

      class << self
        # Load tokens with fallback chain:
        # 1. macOS Keychain (Claude Code's OAuth token)
        # 2. Local YAML file (~/.rubyn-code/tokens.yml)
        # 3. ANTHROPIC_API_KEY environment variable
        def load
          load_from_keychain || load_from_file || load_from_env
        end

        # Load API key for a given provider. Anthropic uses the full fallback chain.
        # Other providers: stored key → env var.
        def load_for_provider(provider)
          return load if provider == 'anthropic'

          stored = load_provider_key(provider)
          return { access_token: stored, type: :api_key, source: :stored } if stored

          env_key = resolve_env_key(provider)
          api_key = ENV.fetch(env_key, nil)
          api_key&.empty? == false ? { access_token: api_key, type: :api_key, source: :env } : nil
        end

        # Store an API key for a provider in tokens.yml.
        def save_provider_key(provider, key)
          ensure_directory!
          data = load_tokens_file || {}
          data['provider_keys'] ||= {}
          data['provider_keys'][provider.to_s] = key
          File.write(tokens_path, YAML.dump(data))
          File.chmod(0o600, tokens_path)
        end

        # Retrieve a stored API key for a provider.
        def load_provider_key(provider)
          data = load_tokens_file
          data&.dig('provider_keys', provider.to_s)
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

        def valid?
          tokens = self.load
          return false unless tokens&.fetch(:access_token, nil)
          return true if tokens[:type] == :api_key
          return true unless tokens[:expires_at]

          tokens[:expires_at] > Time.now + EXPIRY_BUFFER_SECONDS
        end

        def exists? = valid?
        def access_token = self.load&.fetch(:access_token, nil)

        private

        def resolve_env_key(provider)
          default = Config::Defaults::PROVIDER_ENV_KEYS.fetch(provider, "#{provider.upcase}_API_KEY")
          Config::Settings.new.provider_config(provider)&.fetch('env_key', nil) || default
        rescue StandardError
          default
        end

        def load_from_keychain
          return nil unless RUBY_PLATFORM.include?('darwin')

          output = `security find-generic-password -s "#{KEYCHAIN_SERVICE}" -w 2>/dev/null`.strip
          return nil if output.empty?

          oauth = JSON.parse(output)['claudeAiOauth']
          return nil unless oauth&.dig('accessToken')

          build_keychain_tokens(oauth)
        rescue StandardError
          nil
        end

        def build_keychain_tokens(oauth)
          {
            access_token: oauth['accessToken'],
            refresh_token: oauth['refreshToken'],
            expires_at: oauth['expiresAt'] ? Time.at(oauth['expiresAt'] / 1000.0) : nil,
            type: :oauth,
            source: :keychain
          }
        end

        def load_from_file
          return nil unless File.exist?(tokens_path)

          data = YAML.safe_load_file(tokens_path, permitted_classes: [Time])
          return nil unless data.is_a?(Hash)
          return nil unless data['access_token']

          {
            access_token: data['access_token'],
            refresh_token: data['refresh_token'],
            expires_at: parse_time(data['expires_at']),
            type: :oauth,
            source: :file
          }
        rescue Psych::SyntaxError, Errno::EACCES
          nil
        end

        def load_from_env
          api_key = ENV.fetch('ANTHROPIC_API_KEY', nil)
          return nil unless api_key && !api_key.empty?

          { access_token: api_key, refresh_token: nil, expires_at: nil, type: :api_key, source: :env }
        end

        def load_tokens_file
          return nil unless File.exist?(tokens_path)

          data = YAML.safe_load_file(tokens_path, permitted_classes: [Time])
          data.is_a?(Hash) ? data : nil
        rescue Psych::SyntaxError, Errno::EACCES
          nil
        end

        def tokens_path = Config::Defaults::TOKENS_FILE

        def ensure_directory!
          FileUtils.mkdir_p(File.dirname(tokens_path))
          File.chmod(0o700, File.dirname(tokens_path))
        end

        def parse_time(value)
          case value
          when Time then value
          when String then Time.parse(value)
          when Integer, Float then Time.at(value)
          end
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
