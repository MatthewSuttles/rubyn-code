# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class InstallSkills < Base
        def self.command_name = '/install-skills'
        def self.description = 'Install skill packs from the registry'

        def execute(args, ctx) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength -- command dispatch with flags
          global = args.delete('--global')
          update = args.delete('--update')

          installer = build_installer(ctx, global: !global.nil?)

          if update && args.empty?
            update_all(installer, ctx)
          elsif args.empty?
            show_usage(ctx)
          else
            install_packs(installer, args, update: !update.nil?, ctx: ctx)
          end
        rescue Skills::RegistryError => e
          ctx.renderer.error("Registry error: #{e.message}")
        rescue StandardError => e
          ctx.renderer.error("Install failed: #{e.message}")
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

        def install_packs(installer, names, update:, ctx:)
          results = installer.install(names, update: update) do |event, data|
            report_progress(event, data, ctx)
          end

          summary = build_summary(results)
          ctx.renderer.info(summary) unless summary.empty?

          reload_skills(ctx)
        end

        def update_all(installer, ctx)
          installed = installer.installed_packs
          if installed.empty?
            ctx.renderer.info('No skill packs installed. Use /install-skills <name> to install one.')
            return
          end

          ctx.renderer.info('Checking for updates...')
          results = installer.update_all do |event, data|
            report_progress(event, data, ctx)
          end

          updated = results.select { |r| r[:status] == :installed }
          if updated.empty?
            ctx.renderer.info('All packs are up to date.')
          else
            ctx.renderer.success("Updated #{updated.size} pack(s).")
          end

          reload_skills(ctx)
        end

        def report_progress(event, data, ctx)
          case event
          when :fetching
            ctx.renderer.info("Fetching #{data[:name]} pack from rubyn.ai...")
          when :downloading
            ctx.renderer.info("  Downloading #{data[:total]} skill files...")
          when :installed
            data[:files].each { |f| puts "  → #{data[:name]}/#{f}" }
            ctx.renderer.success("Installed #{data[:files].size} skills to .rubyn-code/skills/#{data[:name]}/")
          when :up_to_date
            ctx.renderer.info("#{data[:name]} is already installed (v#{data[:version]}). Use --update to refresh.")
          when :error
            ctx.renderer.error("Failed to install #{data[:name]}: #{data[:message]}")
          end
        end

        def build_summary(results)
          installed = results.select { |r| r[:status] == :installed }
          return '' if installed.empty?

          total_files = installed.sum { |r| r[:files].size }
          "These skills load on demand when you work with related code. (#{total_files} files installed)"
        end

        def reload_skills(ctx)
          return unless ctx.skill_loader.respond_to?(:catalog)

          # Force the catalog to rebuild its index so new packs are available immediately
          catalog = ctx.skill_loader.catalog
          catalog.instance_variable_set(:@index, nil) if catalog.respond_to?(:available)
        end

        def show_usage(ctx)
          ctx.renderer.info('Usage: /install-skills <name> [name2] [name3]')
          ctx.renderer.info('       /install-skills --update')
          ctx.renderer.info('       /install-skills --global <name>')
          ctx.renderer.info('')
          ctx.renderer.info('Install skill packs from rubyn.ai. Packs add domain-specific')
          ctx.renderer.info('knowledge for popular gems and patterns.')
          ctx.renderer.info('')
          ctx.renderer.info('Use /skills --available to browse the catalog.')
        end
      end
    end
  end
end
