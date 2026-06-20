# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # `/megaplan` REPL command — mirrors the VS Code chat's chat-resident
      # megaplan entry. Loads the megaplan skill (from the shared
      # skills catalog) into the conversation, flips plan mode ON so the
      # agent is restricted to read-only tools, and kicks off a
      # conversational interview.
      #
      # The interview itself is chat-style here (multi-turn natural-
      # language Q&A), not the structured question-card UI the VS Code
      # extension uses. Same skill content driving both surfaces.
      class Megaplan < Base
        def self.command_name = '/megaplan'
        def self.description  = 'Plan a feature in phases (interview, then numbered phase docs)'
        def self.aliases      = ['/mega-plan'].freeze

        def execute(args, ctx)
          content = ctx.skill_loader.load('megaplan')
          ctx.conversation.add_user_message("<skill>#{content}</skill>")
          ctx.renderer.info('Megaplan mode — interviewer with read-only tools 🧠')

          ctx.send_message(build_prompt(args.join(' ').strip))

          { action: :set_plan_mode, enabled: true }
        rescue StandardError => e
          ctx.renderer.error("Megaplan error: #{e.message}")
          nil
        end

        private

        def build_prompt(feature)
          base = <<~PROMPT.strip
            Conduct a megaplan interview, following the megaplan skill loaded above.
            Stay strictly read-only: you may inspect files, search code, and check
            git state, but do NOT edit, write, run shell mutations, or call any
            destructive tool. Ask ONE question at a time. When you have enough,
            output the final phase breakdown as a numbered outline.
          PROMPT
          return base if feature.empty?

          "#{base}\n\nThe feature to plan: #{feature}"
        end
      end
    end
  end
end
