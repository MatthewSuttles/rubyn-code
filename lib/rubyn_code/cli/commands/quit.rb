# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Quit < Base
        def self.command_name = '/quit'
        def self.description = 'Exit Rubyn Code'
        def self.aliases = ['/exit', '/q'].freeze

        def execute(_args, _ctx)
          :quit
        end
      end
    end
  end
end
