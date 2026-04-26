# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class InstallSkills < Base
        def self.command_name = '/install-skills'
        def self.description = 'Install skill packs from the Rubyn registry'

        def execute(args, ctx)
          if args.empty?
            ctx.renderer.warning('Usage: /install-skills <pack-name> [pack-name ...]')
            return
          end

          pack_manager = Skills::PackManager.new
          registry = Skills::RegistryClient.new

          args.each { |name| install_pack(name, registry, pack_manager, ctx) }
        rescue Skills::RegistryError => e
          ctx.renderer.error(e.message)
        end

        private

        def install_pack(name, registry, pack_manager, ctx)
          if pack_manager.installed?(name)
            ctx.renderer.warning("Pack '#{name}' is already installed. Use /remove-skills first to reinstall.")
            return
          end

          ctx.renderer.info("Fetching pack '#{name}' from registry...")
          pack_data = registry.fetch_pack(name)
          pack_manager.install(pack_data)
          ctx.renderer.info("Installed skill pack '#{name}' successfully.")
        rescue Skills::RegistryError => e
          ctx.renderer.error("Failed to install '#{name}': #{e.message}")
        rescue ArgumentError => e
          ctx.renderer.error("Invalid pack data for '#{name}': #{e.message}")
        end
      end
    end
  end
end
