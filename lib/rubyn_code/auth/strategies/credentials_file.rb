# frozen_string_literal: true

require 'json'
require_relative 'base'

module RubynCode
  module Auth
    module Strategies
      # Reads Claude Code's OAuth token from a plain JSON file.
      # Used on Linux/other where no system keychain is available.
      class CredentialsFile < Base
        SOURCE = :credentials_file

        def self.display_name = 'Claude credentials file'

        def self.setup_hint
          'Run Claude Code once to authenticate (~/.claude/.credentials.json)'
        end

        # @return [TokenResult, nil]
        def call
          path = Config::Defaults::CLAUDE_CREDENTIALS_FILE
          return nil unless File.exist?(path)

          warn_insecure_permissions(path)

          oauth = JSON.parse(File.read(path))['claudeAiOauth']
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

        def parse_expires_at(millis)
          return nil unless millis

          Time.at(millis / 1000.0)
        end

        def warn_insecure_permissions(path)
          mode = File.stat(path).mode & 0o777
          return if mode == 0o600

          warn "[rubyn-code] WARNING: #{path} has mode #{format('%04o', mode)}, expected 0600"
        rescue SystemCallError
          # stat can fail on exotic filesystems — don't block auth
          nil
        end
      end
    end
  end
end
