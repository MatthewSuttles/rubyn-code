# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Plan < Base
        def self.command_name = '/plan'
        def self.description = 'Toggle plan mode (think before acting)'

        def execute(_args, ctx)
          if ctx.plan_mode?
            ctx.renderer.info('Plan mode OFF — back to full execution. 🚀')
            { action: :set_plan_mode, enabled: false }
          else
            ctx.renderer.info("Plan mode ON — read-only tools only. I can explore but won't change anything. 🧠")
            { action: :set_plan_mode, enabled: true }
          end
        end
      end
    end
  end
end
