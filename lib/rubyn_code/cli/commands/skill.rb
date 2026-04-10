# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Skill < Base
        def self.command_name = '/skill'
        def self.description = 'Load a skill or list available skills'

        def execute(args, ctx)
          args.first ? load_skill(args.first, ctx) : list_skills(ctx)
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
      end
    end
  end
end
