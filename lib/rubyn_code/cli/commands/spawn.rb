# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Spawn < Base
        def self.command_name = '/spawn'
        def self.description = 'Spawn a teammate agent (/spawn <name> [role])'

        def execute(args, ctx)
          name = args[0]
          unless name
            ctx.renderer.error('Usage: /spawn <name> [role]')
            return
          end

          role = args[1] || 'coder'

          { action: :spawn_teammate, name: name, role: role }
        end
      end
    end
  end
end
