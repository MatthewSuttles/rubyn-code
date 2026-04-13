# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      # Handles "config/get" JSON-RPC requests from the IDE extension.
      #
      # When a key is provided, returns that single setting with its source.
      # When no key is provided, returns all configurable settings plus
      # provider definitions so the extension can populate its UI.
      class ConfigGetHandler
        EXPOSED_KEYS = %w[
          provider model model_mode max_iterations max_sub_agent_iterations max_output_chars
          context_threshold_tokens session_budget_usd daily_budget_usd
        ].freeze

        def initialize(server)
          @server = server
        end

        def call(params)
          settings = Config::Settings.new
          key = params['key']

          if key
            single_key_response(settings, key)
          else
            all_settings_response(settings)
          end
        end

        private

        def single_key_response(settings, key)
          unless EXPOSED_KEYS.include?(key.to_s)
            return { 'key' => key, 'value' => nil, 'source' => 'unknown',
                     'error' => "Unknown config key: #{key}" }
          end

          value = settings.get(key)
          source = settings.data.key?(key.to_s) ? 'config_file' : 'default'

          { 'key' => key, 'value' => value, 'source' => source }
        end

        def all_settings_response(settings)
          result = {}

          EXPOSED_KEYS.each do |key|
            sym = key.to_sym
            value = settings.get(key)
            default = Config::Settings::DEFAULT_MAP[sym]
            result[key] = { 'value' => value, 'default' => default }
          end

          providers = settings.data['providers'] || {}

          { 'settings' => result, 'providers' => providers }
        end
      end
    end
  end
end
