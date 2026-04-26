# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Skills < Base
        def self.command_name = '/skills'
        def self.description = 'List installed skill packs or browse the registry'

        def execute(args, ctx)
          case args.first
          when 'search' then search_registry(args[1..].join(' '), ctx)
          when 'available' then list_available(ctx)
          when nil, 'list' then list_installed(ctx)
          else
            ctx.renderer.warning(
              "Unknown subcommand '#{args.first}'. Try: /skills, /skills available, /skills search <term>"
            )
          end
        rescue RubynCode::Skills::RegistryError => e
          ctx.renderer.error(e.message)
        end

        private

        def list_installed(ctx)
          packs = RubynCode::Skills::PackManager.new.installed

          if packs.empty?
            ctx.renderer.info(
              'No skill packs installed. Use /skills available to browse or /install-skills <name> to install.'
            )
            return
          end

          ctx.renderer.info("Installed skill packs (#{packs.size}):")
          packs.each { |pack| puts "  #{format_installed_pack(pack)}" }
        end

        def list_available(ctx)
          ctx.renderer.info('Fetching available packs from registry...')
          result = RubynCode::Skills::RegistryClient.new.fetch_catalog
          packs = result[:data]
          return ctx.renderer.info('No packs found in the registry.') unless valid_results?(packs)

          pack_manager = RubynCode::Skills::PackManager.new
          ctx.renderer.info("Available skill packs (#{packs.size}):")
          packs.each { |pack| puts "  #{format_available_pack(pack, pack_manager)}" }
        end

        def search_registry(term, ctx)
          if term.nil? || term.strip.empty?
            ctx.renderer.warning('Usage: /skills search <term>')
            return
          end

          query = term.strip
          ctx.renderer.info("Searching registry for '#{query}'...")
          result = RubynCode::Skills::RegistryClient.new.search_packs(query)
          packs = result[:data]

          unless valid_results?(packs)
            ctx.renderer.info("No packs found matching '#{query}'.")
            return
          end

          ctx.renderer.info("Packs matching '#{query}' (#{packs.size}):")
          packs.each { |pack| puts "  #{format_pack_line(pack)}" }
        end

        def valid_results?(results)
          results.is_a?(Array) && !results.empty?
        end

        def format_installed_pack(pack)
          version = pack[:version] ? " v#{pack[:version]}" : ''
          desc = pack[:description].to_s.empty? ? '' : " — #{pack[:description]}"
          "#{pack[:name]}#{version}#{desc}"
        end

        def format_available_pack(pack, pack_manager)
          name = pack_name(pack)
          installed = pack_manager.installed?(name) ? ' [installed]' : ''
          "#{format_pack_line(pack)}#{installed}"
        end

        def format_pack_line(pack)
          name = pack_name(pack)
          desc = pack_description(pack)
          label = desc.empty? ? '' : " — #{desc}"
          "#{name}#{label}"
        end

        def pack_name(pack)
          pack[:name] || pack['name']
        end

        def pack_description(pack)
          (pack[:description] || pack['description']).to_s
        end
      end
    end
  end
end
