# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles "config/set" JSON-RPC requests from the IDE extension.
      #
      # Validates the key is in the allowed list, coerces types as needed,
      # persists the change, and notifies the client via config/changed.
      class ConfigSetHandler
        EXPOSED_KEYS = ConfigGetHandler::EXPOSED_KEYS

        NUMERIC_KEYS = %w[
          max_iterations max_sub_agent_iterations max_output_chars
          context_threshold_tokens session_budget_usd daily_budget_usd
        ].freeze

        STRING_KEYS = %w[provider model].freeze

        def initialize(server)
          @server = server
        end

        def call(params)
          key = params['key'].to_s
          value = params['value']

          return { 'updated' => false, 'error' => "Unknown config key: #{key}" } unless EXPOSED_KEYS.include?(key)

          value = coerce(key, value)

          settings = Config::Settings.new
          settings.set(key, value)
          settings.save!

          @server.notify('config/changed', { 'key' => key, 'value' => value })

          { 'updated' => true, 'key' => key, 'value' => value }
        end

        private

        def coerce(key, value)
          if NUMERIC_KEYS.include?(key)
            numeric_value(value)
          else
            value.to_s
          end
        end

        def numeric_value(value)
          return value if value.is_a?(Numeric)

          str = value.to_s
          str.include?('.') ? Float(str) : Integer(str)
        rescue ArgumentError, TypeError
          value
        end
      end
    end
  end
end
