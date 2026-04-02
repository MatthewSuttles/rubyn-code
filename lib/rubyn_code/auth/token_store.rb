# frozen_string_literal: true

require "yaml"
require "fileutils"
require "json"
require "time"

module RubynCode
  module Auth
    module TokenStore
      EXPIRY_BUFFER_SECONDS = 300 # 5 minutes
      KEYCHAIN_SERVICE = "Claude Code-credentials"

      class << self
        # Load tokens with fallback chain:
        # 1. macOS Keychain (Claude Code's OAuth token)
        # 2. Local YAML file (~/.rubyn-code/tokens.yml)
        # 3. ANTHROPIC_API_KEY environment variable
        def load
          load_from_keychain || load_from_file || load_from_env
        end

        def save(access_token:, refresh_token:, expires_at:)
          ensure_directory!

          data = {
            "access_token" => access_token,
            "refresh_token" => refresh_token,
            "expires_at" => expires_at.is_a?(Time) ? expires_at.iso8601 : expires_at.to_s
          }

          File.write(tokens_path, YAML.dump(data))
          File.chmod(0o600, tokens_path)
          data
        end

        def clear!
          File.delete(tokens_path) if File.exist?(tokens_path)
          true
        end

        def valid?
          tokens = self.load
          return false unless tokens
          return false unless tokens[:access_token]

          # API keys don't expire
          return true if tokens[:type] == :api_key

          # OAuth tokens need expiry check
          return true unless tokens[:expires_at]

          tokens[:expires_at] > Time.now + EXPIRY_BUFFER_SECONDS
        end

        def exists?
          valid?
        end

        def access_token
          tokens = self.load
          tokens&.fetch(:access_token, nil)
        end

        def token_type
          tokens = self.load
          tokens&.fetch(:type, :oauth)
        end

        private

        # Read Claude Code's OAuth token from macOS Keychain
        def load_from_keychain
          return nil unless RUBY_PLATFORM.include?("darwin")

          output = `security find-generic-password -s "#{KEYCHAIN_SERVICE}" -w 2>/dev/null`.strip
          return nil if output.empty?

          data = JSON.parse(output)
          oauth = data["claudeAiOauth"]
          return nil unless oauth && oauth["accessToken"]

          expires_at = if oauth["expiresAt"]
                         Time.at(oauth["expiresAt"] / 1000.0) # milliseconds to seconds
                       end

          {
            access_token: oauth["accessToken"],
            refresh_token: oauth["refreshToken"],
            expires_at: expires_at,
            type: :oauth,
            source: :keychain
          }
        rescue JSON::ParserError, StandardError
          nil
        end

        # Read from local YAML token file
        def load_from_file
          return nil unless File.exist?(tokens_path)

          data = YAML.safe_load_file(tokens_path, permitted_classes: [Time])
          return nil unless data.is_a?(Hash)
          return nil unless data["access_token"]

          {
            access_token: data["access_token"],
            refresh_token: data["refresh_token"],
            expires_at: parse_time(data["expires_at"]),
            type: :oauth,
            source: :file
          }
        rescue Psych::SyntaxError, Errno::EACCES
          nil
        end

        # Fall back to ANTHROPIC_API_KEY environment variable
        def load_from_env
          api_key = ENV["ANTHROPIC_API_KEY"]
          return nil unless api_key && !api_key.empty?

          {
            access_token: api_key,
            refresh_token: nil,
            expires_at: nil,
            type: :api_key,
            source: :env
          }
        end

        def tokens_path
          Config::Defaults::TOKENS_FILE
        end

        def ensure_directory!
          dir = File.dirname(tokens_path)
          FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
          File.chmod(0o700, dir)
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
