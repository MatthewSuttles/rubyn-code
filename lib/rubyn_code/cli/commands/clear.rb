# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Clear < Base
        def self.command_name = '/clear'
        def self.description = 'Clear the terminal'

        def execute(_args, _ctx)
          system('clear')
        end
      end
    end
  end
end
