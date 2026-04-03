# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Version < Base
        def self.command_name = '/version'
        def self.description = 'Show version info'

        def execute(_args, ctx)
          ctx.renderer.info("Rubyn Code v#{RubynCode::VERSION}")
        end
      end
    end
  end
end
