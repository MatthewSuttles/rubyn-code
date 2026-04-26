# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class RemoveSkills < Base
        def self.command_name = '/remove-skills'
        def self.description = 'Remove installed skill packs'

        def execute(args, ctx)
          if args.empty?
            ctx.renderer.warning('Usage: /remove-skills <pack-name> [pack-name ...]')
            return
          end

          pack_manager = RubynCode::Skills::PackManager.new

          args.each { |name| remove_pack(name, pack_manager, ctx) }
        end

        private

        def remove_pack(name, pack_manager, ctx)
          unless pack_manager.installed?(name)
            ctx.renderer.warning("Pack '#{name}' is not installed.")
            return
          end

          pack_manager.remove(name)
          ctx.renderer.info("Removed skill pack '#{name}'.")
        end
      end
    end
  end
end
