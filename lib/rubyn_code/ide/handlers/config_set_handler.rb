# frozen_string_literal: true

require_relative '../../config/validator'

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

        STRING_KEYS = %w[provider model model_mode].freeze

        VALID_PERMISSION_MODES = %w[default accept_edits plan_only auto dont_ask bypass].freeze

        def initialize(server)
          @server = server
        end

        def call(params)
          key = params['key'].to_s
          value = params['value']

          return { 'updated' => false, 'error' => "Unknown config key: #{key}" } unless EXPOSED_KEYS.include?(key)

          # permission_mode is a runtime-only setting on the server, not persisted to config.
          if key == 'permission_mode'
            mode = value.to_s
            unless VALID_PERMISSION_MODES.include?(mode)
              return { 'updated' => false,
                       'error' => "Invalid permission mode: #{mode}. " \
                                  "Valid modes: #{VALID_PERMISSION_MODES.join(', ')}" }
            end

            @server.permission_mode = mode.to_sym
            @server.tool_output_adapter&.permission_mode = mode.to_sym
            @server.notify('config/changed', { 'key' => key, 'value' => mode })
            return { 'updated' => true, 'key' => key, 'value' => mode }
          end

          value = coerce(key, value)

          result = Config::Validator.new.validate(key, value)
          unless result[:valid]
            return { 'updated' => false, 'error' => result[:errors].join('; ') }
          end

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
