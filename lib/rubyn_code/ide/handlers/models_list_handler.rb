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
            'modelMode' => settings.get('model_mode', 'auto')
          }
        end

        private

        def collect_models(providers)
          models = []
          providers.each do |name, cfg|
            next unless cfg.is_a?(Hash)

            provider_models = cfg['models']
            case provider_models
            when Hash
              provider_models.each do |tier, model_name|
                models << { 'provider' => name, 'model' => model_name, 'tier' => tier }
              end
            when Array
              provider_models.each do |model_name|
                models << { 'provider' => name, 'model' => model_name, 'tier' => '-' }
              end
            end
          end
          models
        end
      end
    end
  end
end
