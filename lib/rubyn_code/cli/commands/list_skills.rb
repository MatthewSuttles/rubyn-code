# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class ListSkills < Base
        def self.command_name = '/skills'
        def self.description = 'List installed skills or browse the registry'

        def execute(args, ctx)
          if args.include?('--available')
            list_available(ctx)
          else
            list_installed(ctx)
          end
        rescue Skills::RegistryError => e
          ctx.renderer.error("Registry error: #{e.message}")
        rescue StandardError => e
          ctx.renderer.error("Skills error: #{e.message}")
        end

        private

        def list_installed(ctx)
          catalog = ctx.skill_loader.catalog
          all_skills = catalog.available
          buckets = partition_skills(all_skills, ctx)

          ctx.renderer.info("Loaded skills (#{all_skills.size} total)")
          puts

          render_builtin(buckets[:builtin], catalog)
          render_packs(buckets[:packs])
          render_community(buckets[:community], buckets[:packs].any?)
        end

        def partition_skills(all_skills, ctx)
          community_dir = File.join(ctx.project_root, '.rubyn-code', 'skills')
          global_dir = File.join(Config::Defaults::HOME_DIR, 'skills')
          pack_dir = File.join(Config::Defaults::HOME_DIR, 'skill-packs')

          buckets = { builtin: [], community: [], packs: [] }
          all_skills.each do |skill|
            buckets[bucket_for(skill[:path].to_s, pack_dir, community_dir, global_dir)] << skill
          end
          buckets
        end

        def bucket_for(path, pack_dir, community_dir, global_dir)
          return :packs if path.start_with?(pack_dir)
          return :community if path.start_with?(community_dir) || path.start_with?(global_dir)

          :builtin
        end

        def render_builtin(builtin, catalog)
          puts "  Built-in (#{builtin.size})"
          builtin.group_by { |s| category_from_path(s[:path], catalog.skills_dirs) }
                 .sort_by { |cat, _| cat }
                 .each do |cat, skills|
            label = cat.empty? ? 'general' : cat
            puts "    #{label}: #{skills.map { |s| s[:name] }.join(', ')}"
          end
        end

        def render_packs(packs)
          return if packs.empty?

          puts
          summary = packs.group_by { |s| pack_from_path(s[:path]) }
                         .sort
                         .map { |pack, skills| "#{pack} (#{skills.size})" }
                         .join(', ')
          puts "  Skill packs: #{summary}"
        end

        def render_community(community, packs_present)
          if community.any?
            puts
            summary = community.group_by { |s| pack_from_path(s[:path]) }
                               .map { |pack, skills| "#{pack} (#{skills.size})" }
                               .join(', ')
            puts "  Community: #{summary}"
          elsif !packs_present
            puts
            puts '  Skill packs: none installed'
            puts '  Run /skills --available to browse, or /install-skills <name> to install.'
          end
        end

        def list_available(ctx) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- readable catalog display
          client = Skills::RegistryClient.new
          catalog_data = client.fetch_catalog
          packs = catalog_data['packs'] || []

          if packs.empty?
            ctx.renderer.info('No packs available in the registry.')
            return
          end

          installer = Skills::PackInstaller.new(
            registry_client: client,
            project_root: ctx.project_root
          )

          ctx.renderer.info("Available skill packs (#{packs.size})")
          puts

          # Group by category
          by_category = packs.group_by { |p| p['category'] || 'other' }
          by_category.sort_by { |cat, _| cat }.each do |category, cat_packs|
            puts "  #{category.capitalize}"
            cat_packs.each do |pack|
              installed = installer.installed?(pack['name'])
              marker = installed ? ' ✓' : ''
              desc = pack['description']&.slice(0, 50) || ''
              puts "    #{pack['name'].ljust(20)} #{desc}  (#{pack['skillCount']} skills)#{marker}"
            end
            puts
          end

          puts '  Install with: /install-skills <name>'
        end

        def category_from_path(path, skills_dirs)
          skills_dirs.each do |dir|
            expanded = File.expand_path(dir)
            next unless path.to_s.start_with?(expanded)

            relative = path.delete_prefix("#{expanded}/")
            parts = relative.split('/')
            return parts.size > 1 ? parts.first : ''
          end
          ''
        end

        def pack_from_path(path)
          # Pack-style layouts: .rubyn-code/skills/<pack>/<file>.md
          # or .rubyn-code/skill-packs/<pack>/<file>.md
          parts = path.to_s.split('/')
          idx = parts.rindex('skill-packs') || parts.rindex('skills')
          return 'unknown' unless idx

          parts[idx + 1] || 'unknown'
        end
      end
    end
  end
end
