# frozen_string_literal: true

module RubynCode
  module IDE
    module Handlers
      class ModelsListHandler
        def initialize(server)
          @server = server
        end

        def call(_params)
          settings = Config::Settings.new
          providers = settings.data['providers'] || {}

          {
            'models' => collect_models(providers),
            'activeProvider' => settings.provider,
            'activeModel' => settings.model,
            'modelMode' => settings.get('model_mode', 'auto'),
            'connectedProviders' => connected_providers(providers)
          }
        end

        private

        def connected_providers(providers)
          providers.keys.select do |name|
            token = Auth::TokenStore.load_for_provider(name)
            token && token[:access_token].to_s != ''
          rescue StandardError
            false
          end
        end

        def collect_models(providers)
          models = []
          providers.each do |name, cfg|
            next unless cfg.is_a?(Hash)

            configured = cfg['models']
            if configured.is_a?(Hash)
              configured.each do |tier, model_name|
                models << { 'provider' => name, 'model' => model_name, 'tier' => tier }
              end
            else
              Array(configured).each do |model_name|
                models << { 'provider' => name, 'model' => model_name, 'tier' => 'custom' }
              end
            end
          end
          models
        end
      end
    end
  end
end
