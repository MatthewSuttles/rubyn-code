# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Cost < Base
        def self.command_name = '/cost'
        def self.description = 'Show token usage and costs'

        def execute(_args, ctx)
          ctx.renderer.cost_summary(
            session_cost: ctx.budget_enforcer.session_cost,
            daily_cost: ctx.budget_enforcer.daily_cost,
            tokens: {
              input: ctx.context_manager.total_input_tokens,
              output: ctx.context_manager.total_output_tokens
            }
          )
        end
      end
    end
  end
end
