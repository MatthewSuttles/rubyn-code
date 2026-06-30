# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # Toggle extended thinking on/off and optionally set the budget.
      #
      #   /think             # show current budget
      #   /think off         # disable
      #   /think <budget>    # enable with <budget> tokens (e.g. /think 8192)
      class Think < Base
        DEFAULT_BUDGET = 8_192

        def self.command_name = '/think'
        def self.description = 'Toggle or set extended thinking budget (tokens)'

        def execute(args, ctx)
          arg = args.first

          current = ctx.llm_client.respond_to?(:thinking_budget_tokens) ? ctx.llm_client.thinking_budget_tokens : 0

          case arg
          when nil
            show_status(current, ctx)
          when 'off', '0'
            ctx.llm_client.thinking_budget_tokens = 0
            ctx.renderer.info('Extended thinking OFF 🧠✋')
          when /\A\d+\z/
            budget = arg.to_i
            ctx.llm_client.thinking_budget_tokens = budget
            ctx.renderer.info("Extended thinking ON — budget: #{budget} tokens 🧠")
          else
            ctx.renderer.warning("Usage: /think [off|<budget>]. Got: #{arg}")
          end
        end

        private

        def show_status(current, ctx)
          state = current.to_i.positive? ? "ON (#{current} tokens)" : 'OFF'
          ctx.renderer.info("Extended thinking: #{state}")
          ctx.renderer.info('Usage: /think <budget>  e.g. /think 8192   (or /think off)')
        end
      end
    end
  end
end
