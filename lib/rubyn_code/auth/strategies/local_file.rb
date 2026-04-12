# frozen_string_literal: true

require 'yaml'
require 'time'
require_relative 'base'

module RubynCode
  module Auth
    module Strategies
      # Reads tokens from rubyn-code's own YAML file at ~/.rubyn-code/tokens.yml.
      # This is where rubyn-code writes tokens it obtained via its own OAuth flow.
      class LocalFile < Base
        SOURCE = :file

        def self.display_name = 'local token file'

        def self.setup_hint
          "Run 'rubyn-code --auth' to enter an API key"
        end

        # @return [TokenResult, nil]
        def call
          path = Config::Defaults::TOKENS_FILE
          return nil unless File.exist?(path)

          data = YAML.safe_load_file(path, permitted_classes: [Time])
          return nil unless data.is_a?(Hash) && data['access_token']

          build_result(
            access_token: data['access_token'],
            refresh_token: data['refresh_token'],
            expires_at: parse_time(data['expires_at']),
            type: :oauth,
            source: SOURCE
          )
        rescue Psych::SyntaxError, Errno::EACCES
          nil
        end

        private

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
