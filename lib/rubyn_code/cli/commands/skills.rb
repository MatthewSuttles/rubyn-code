# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Skills < Base
        def self.command_name = '/skills'
        def self.description = 'List installed skill packs or browse the registry'

        def execute(args, ctx)
          case args.first
          when 'search'   then search_registry(args[1..].join(' '), ctx)
          when 'available' then list_available(ctx)
          when nil, 'list' then list_installed(ctx)
          else
            ctx.renderer.warning("Unknown subcommand '#{args.first}'. Try: /skills, /skills available, /skills search <term>")
          end
        rescue Skills::RegistryError => e
          ctx.renderer.error(e.message)
        end

        private

        def list_installed(ctx)
          packs = Skills::PackManager.new.installed

          if packs.empty?
            ctx.renderer.info('No skill packs installed. Use /skills available to browse or /install-skills <name> to install.')
            return
          end

          ctx.renderer.info("Installed skill packs (#{packs.size}):")
          packs.each do |pack|
            version = pack[:version] ? " v#{pack[:version]}" : ''
            desc = pack[:description].to_s.empty? ? '' : " — #{pack[:description]}"
            puts "  #{pack[:name]}#{version}#{desc}"
          end
        end

        def list_available(ctx)
          ctx.renderer.info('Fetching available packs from registry...')
          packs = Skills::RegistryClient.new.list_packs
          pack_manager = Skills::PackManager.new

          if packs.empty? || !packs.is_a?(Array)
            ctx.renderer.info('No packs found in the registry.')
            return
          end

          ctx.renderer.info("Available skill packs (#{packs.size}):")
          packs.each do |pack|
            name = pack[:name] || pack['name']
            desc = (pack[:description] || pack['description']).to_s
            installed = pack_manager.installed?(name) ? ' [installed]' : ''
            label = desc.empty? ? '' : " — #{desc}"
            puts "  #{name}#{label}#{installed}"
          end
        end

        def search_registry(term, ctx)
          if term.nil? || term.strip.empty?
            ctx.renderer.warning('Usage: /skills search <term>')
            return
          end

          ctx.renderer.info("Searching registry for '#{term.strip}'...")
          results = Skills::RegistryClient.new.search_packs(term.strip)

          if results.empty? || !results.is_a?(Array)
            ctx.renderer.info("No packs found matching '#{term.strip}'.")
            return
          end

          ctx.renderer.info("Packs matching '#{term.strip}' (#{results.size}):")
          results.each do |pack|
            name = pack[:name] || pack['name']
            desc = (pack[:description] || pack['description']).to_s
            label = desc.empty? ? '' : " — #{desc}"
            puts "  #{name}#{label}"
          end
        end
      end
    end
  end
end
