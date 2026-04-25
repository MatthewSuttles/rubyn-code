# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class RemoveSkills < Base
        def self.command_name = '/remove-skills'
        def self.description = 'Remove an installed skill pack'

        def execute(args, ctx)
          if args.empty?
            ctx.renderer.info('Usage: /remove-skills <name>')
            return
          end

          name = args.first
          global = args.include?('--global')
          installer = build_installer(ctx, global: global)

          unless installer.installed?(name)
            ctx.renderer.warning("Skill pack '#{name}' is not installed.")
            return
          end

          manifest = installer.read_manifest(name)
          file_count = manifest ? manifest['skillCount'] : '?'

          ctx.renderer.warning("Remove #{name} (#{file_count} skills)? This cannot be undone.")
          print '  Confirm (y/N): '
          $stdout.flush

          answer = $stdin.gets&.strip&.downcase
          unless %w[y yes].include?(answer)
            ctx.renderer.info('Cancelled.')
            return
          end

          installer.remove(name)
          ctx.renderer.success("Removed skill pack '#{name}'.")
          reload_skills(ctx)
        rescue StandardError => e
          ctx.renderer.error("Remove failed: #{e.message}")
        end

        private

        def build_installer(ctx, global: false)
          client = Skills::RegistryClient.new
          Skills::PackInstaller.new(
            registry_client: client,
            project_root: ctx.project_root,
            global: global
          )
        end

        def reload_skills(ctx)
          return unless ctx.skill_loader.respond_to?(:catalog)

          catalog = ctx.skill_loader.catalog
          catalog.instance_variable_set(:@index, nil) if catalog.respond_to?(:available)
        end
      end
    end
  end
end
