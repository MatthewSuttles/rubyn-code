# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Skill < Base
        def self.command_name = '/skill'
        def self.description = 'Load a skill or list available skills'

        def execute(args, ctx)
          return list_skills(ctx) if args.empty?

          case args.first
          when 'search' then search_skills(args[1..].join(' '), ctx)
          when 'list'   then list_by_category(args[1], ctx)
          else               load_skill(args.first, ctx)
          end
        rescue StandardError => e
          ctx.renderer.error("Skill error: #{e.message}")
        end

        private

        def load_skill(name, ctx)
          content = ctx.skill_loader.load(name)
          ctx.renderer.info("Loaded skill: #{name}")
          ctx.conversation.add_user_message("<skill>#{content}</skill>")
        end

        def list_skills(ctx)
          skills = ctx.skill_loader.catalog.available
          ctx.renderer.info("Available skills (#{skills.size}):")
          skills.each { |skill| puts "  /#{skill[:name]}: #{skill[:description]}" }
        end

        def search_skills(term, ctx) # rubocop:disable Metrics/AbcSize -- readable sequential display logic
          if term.nil? || term.strip.empty?
            ctx.renderer.warning('Usage: /skill search <term>')
            return
          end

          results = ctx.skill_loader.catalog.search(term.strip)
          if results.empty?
            ctx.renderer.info("No skills found matching '#{term.strip}'")
            return
          end

          ctx.renderer.info("Skills matching '#{term.strip}' (#{results.size}):")
          display_entries(results)
        end

        def list_by_category(category, ctx) # rubocop:disable Metrics/AbcSize -- readable sequential display logic
          catalog = ctx.skill_loader.catalog
          return list_categories(catalog, ctx) if category.nil? || category.strip.empty?

          results = catalog.by_category(category.strip)
          if results.empty?
            ctx.renderer.info("No skills found in category '#{category.strip}'")
            return
          end

          ctx.renderer.info("Skills in '#{category.strip}' (#{results.size}):")
          display_entries(results)
        end

        def list_categories(catalog, ctx)
          categories = catalog.categories
          ctx.renderer.info("Skill categories (#{categories.size}):")
          categories.each { |cat| puts "  #{cat}" }
        end

        def display_entries(entries)
          entries.each do |entry|
            desc = entry[:description].to_s.empty? ? '' : " — #{entry[:description]}"
            puts "  /#{entry[:name]}#{desc}"
          end
        end
      end
    end
  end
end
