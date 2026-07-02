# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # Set or clear the reasoning effort level (output_config.effort).
      #
      #   /effort             # show current value
      #   /effort off         # clear back to model default
      #   /effort <level>     # low | medium | high | xhigh | max
      class Effort < Base
        LEVELS = %w[low medium high xhigh max].freeze

        def self.command_name = '/effort'
        def self.description = 'Set reasoning effort (low/medium/high/xhigh/max)'

        def execute(args, ctx)
          arg = args.first

          current = ctx.llm_client.respond_to?(:effort) ? ctx.llm_client.effort : nil

          case arg
          when nil
            show_status(current, ctx)
          when 'off'
            ctx.llm_client.effort = nil
            ctx.renderer.info('Reasoning effort cleared — using model default 🎚️')
          when *LEVELS
            ctx.llm_client.effort = arg
            ctx.renderer.info("Reasoning effort set to #{arg} 🎚️")
          else
            ctx.renderer.warning("Usage: /effort [off|#{LEVELS.join('|')}]. Got: #{arg}")
          end
        end

        private

        def show_status(current, ctx)
          state = current || 'not set (model default: high on 4.6+)'
          ctx.renderer.info("Reasoning effort: #{state}")
          ctx.renderer.info("Usage: /effort <level>  levels: #{LEVELS.join(', ')}   (or /effort off)")
          ctx.renderer.info('Supported on Claude 4.6+ models; xhigh requires Opus 4.7+ / Sonnet 5 / Fable 5.')
        end
      end
    end
  end
end
