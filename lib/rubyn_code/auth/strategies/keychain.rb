# frozen_string_literal: true

require 'json'
require_relative 'base'

module RubynCode
  module Auth
    module Strategies
      # Reads Claude Code's OAuth token from macOS Keychain Services.
      # No-op on non-Darwin platforms.
      class Keychain < Base
        SOURCE = :keychain
        KEYCHAIN_SERVICE = 'Claude Code-credentials'

        def self.display_name = 'macOS Keychain'

        def self.setup_hint
          return nil unless RUBY_PLATFORM.include?('darwin')

          'Run Claude Code once to authenticate (Rubyn reads the OAuth token from your Keychain)'
        end

        # @return [TokenResult, nil]
        def call
          return nil unless macos?

          output = read_keychain
          return nil if output.empty?

          oauth = JSON.parse(output)['claudeAiOauth']
          return nil unless oauth && oauth['accessToken']

          build_result(
            access_token: oauth['accessToken'],
            refresh_token: oauth['refreshToken'],
            expires_at: parse_expires_at(oauth['expiresAt']),
            type: :oauth,
            source: SOURCE
          )
        rescue StandardError
          nil
        end

        private

        def macos?
          RUBY_PLATFORM.include?('darwin')
        end

        def read_keychain
          `security find-generic-password -s "#{KEYCHAIN_SERVICE}" -w 2>/dev/null`.strip
        end

        def parse_expires_at(millis)
          return nil unless millis

          Time.at(millis / 1000.0)
        end
      end
    end
  end
end
