# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'json'
require 'time'

module RubynCode
  module Auth
    module TokenStore # rubocop:disable Metrics/ModuleLength -- single-responsibility credential store
      EXPIRY_BUFFER_SECONDS = 300 # 5 minutes
      KEYCHAIN_SERVICE = 'Claude Code-credentials'

      # Strategy chain: each method returns a token hash or nil.
      # First non-nil result wins. Adding a new auth source is a one-line entry.
      LOAD_STRATEGIES = %i[
        load_from_keychain
        load_from_credentials_file
        load_from_file
        load_from_env
      ].freeze

      class << self
        # Load tokens with fallback chain:
        # 1. macOS Keychain (Claude Code's OAuth token)
        # 2. Claude Code credentials file (~/.claude/.credentials.json)
        # 3. Local YAML file (~/.rubyn-code/tokens.yml)
        # 4. ANTHROPIC_API_KEY environment variable
        def load
          LOAD_STRATEGIES.each do |strategy|
            result = send(strategy)
            return result if result
          end
          nil
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

        # Store an API key for a provider in tokens.yml (encrypted at rest).
        def save_provider_key(provider, key)
          ensure_directory!
          data = load_tokens_file || {}
          data['provider_keys'] ||= {}
          data['provider_keys'][provider.to_s] = KeyEncryption.encrypt(key)
          write_tokens_file(data)
        end

        # Retrieve a stored API key for a provider (decrypted transparently).
        def load_provider_key(provider)
          data = load_tokens_file
          value = data&.dig('provider_keys', provider.to_s)
          return nil unless value

          migrate_plaintext_key!(data, provider, value) unless KeyEncryption.encrypted?(value)
          KeyEncryption.decrypt(value)
        end

        # Delete only one provider key while preserving OAuth tokens and keys
        # for every other configured provider.
        def delete_provider_key(provider) # rubocop:disable Naming/PredicateMethod -- destructive action, not a predicate
          data = load_tokens_file
          keys = data&.fetch('provider_keys', nil)
          return false unless keys.is_a?(Hash) && keys.key?(provider.to_s)

          keys.delete(provider.to_s)
          data.delete('provider_keys') if keys.empty?
          write_tokens_file(data)
          true
        end

        def save(access_token:, refresh_token:, expires_at:)
          ensure_directory!
          data = load_tokens_file || {}
          data['access_token'] = access_token
          data['refresh_token'] = refresh_token
          data['expires_at'] = expires_at.is_a?(Time) ? expires_at.iso8601 : expires_at.to_s
          write_tokens_file(data)
          data
        end

        def clear! # rubocop:disable Naming/PredicateMethod -- destructive action, not a predicate
          FileUtils.rm_f(tokens_path)
          true
        end

        def valid?
          valid_tokens?(self.load)
        end

        # Validate an already-loaded token hash without re-reading the
        # keychain — lets callers cache the result of `load`.
        def valid_tokens?(tokens)
          return false unless tokens&.fetch(:access_token, nil)
          return true if tokens[:type] == :api_key
          return true unless tokens[:expires_at]

          tokens[:expires_at] > Time.now + EXPIRY_BUFFER_SECONDS
        end

        def exists? = valid?
        def access_token = self.load&.fetch(:access_token, nil)

        private

        def resolve_env_key(provider)
          default = Config::Defaults::PROVIDER_ENV_KEYS.fetch(
            provider,
            "#{provider.upcase.tr('-', '_')}_API_KEY"
          )
          Config::Settings.new.provider_config(provider)&.fetch('env_key', nil) || default
        rescue StandardError
          default
        end

        # macOS only: read from Keychain Services
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

        # Linux/other: Claude Code stores OAuth in a plain JSON file
        def load_from_credentials_file
          path = Config::Defaults::CLAUDE_CREDENTIALS_FILE
          return nil unless File.exist?(path)

          warn_insecure_permissions(path)

          oauth = JSON.parse(File.read(path))['claudeAiOauth']
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

        # Warn when credentials file has loose permissions (no system ACLs on Linux)
        def warn_insecure_permissions(path)
          mode = File.stat(path).mode & 0o777
          return if mode == 0o600

          warn "[rubyn-code] WARNING: #{path} has mode #{format('%04o', mode)}, expected 0600"
        rescue StandardError
          nil # best-effort — don't fail a token load over a stat
        end

        def write_tokens_file(data)
          File.write(tokens_path, YAML.dump(data))
          File.chmod(0o600, tokens_path)
        end

        # Auto-encrypt a plaintext key from a pre-encryption install.
        def migrate_plaintext_key!(data, provider, plaintext)
          data['provider_keys'][provider.to_s] = KeyEncryption.encrypt(plaintext)
          write_tokens_file(data)
        rescue StandardError
          nil # don't break reads if migration fails
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
