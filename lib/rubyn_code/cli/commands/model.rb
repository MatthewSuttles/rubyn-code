# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Model < Base
        def self.command_name = '/model'
        def self.description = 'Show or switch model (/model [name])'

        KNOWN_MODELS = %w[
          claude-haiku-4-5
          claude-sonnet-4-20250514
          claude-opus-4-20250514
        ].freeze

        def execute(args, ctx)
          name = args.first

          if name
            unless KNOWN_MODELS.include?(name)
              ctx.renderer.warning("Unknown model: #{name}")
              ctx.renderer.info("Known models: #{KNOWN_MODELS.join(', ')}")
              return
            end

            ctx.renderer.info("Model switched to #{name}")
            { action: :set_model, model: name }
          else
            current = Config::Defaults::DEFAULT_MODEL
            ctx.renderer.info("Current model: #{current}")
            ctx.renderer.info("Available: #{KNOWN_MODELS.join(', ')}")
          end
        end
      end
    end
  end
end
