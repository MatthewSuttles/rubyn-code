# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Budget < Base
        def self.command_name = '/budget'
        def self.description = 'Show or set session budget (/budget [amount])'

        def execute(args, ctx)
          amount = args.first

          if amount
            ctx.renderer.info("Session budget set to $#{amount}")
            { action: :set_budget, amount: amount.to_f }
          else
            remaining = ctx.budget_enforcer.remaining_budget
            ctx.renderer.info("Remaining budget: $#{format('%.4f', remaining)}")
          end
        end
      end
    end
  end
end
