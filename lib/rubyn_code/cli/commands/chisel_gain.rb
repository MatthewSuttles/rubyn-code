# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # `/chisel-gain` — quick read on Chisel's status and what it buys you.
      class ChiselGain < Base
        def self.command_name = '/chisel-gain'
        def self.description = 'Show Chisel status and reference impact'

        # Measured on a real open-source repo for the approach Chisel is built on;
        # shown as an attributed reference, not fabricated per-user metrics (which
        # rubyn-code does not instrument).
        REFERENCE_IMPACT = 'Reference benchmark for this approach (real FastAPI + React repo): ' \
                           '~54% less code, ~20% cheaper, ~27% faster.'

        def execute(_args, ctx)
          mode = RubynCode::Chisel.mode
          debt = RubynCode::Chisel::Debt.scan(ctx.project_root).size

          ctx.renderer.info("Chisel mode: #{mode}")
          ctx.renderer.info('Turn it on with /chisel full.') if mode == 'off'
          ctx.renderer.info("Outstanding chisel: debt markers: #{debt}")
          ctx.renderer.info(REFERENCE_IMPACT)
          ctx.renderer.info('Run /chisel-review for concrete cuts in your current diff.')
        end
      end
    end
  end
end
