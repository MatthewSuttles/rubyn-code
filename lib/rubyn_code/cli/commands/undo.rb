# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Undo < Base
        def self.command_name = '/undo'
        def self.description = 'Remove last exchange'

        def execute(_args, ctx)
          ctx.conversation.undo_last!
          ctx.renderer.info('Last exchange removed.')
        end
      end
    end
  end
end
