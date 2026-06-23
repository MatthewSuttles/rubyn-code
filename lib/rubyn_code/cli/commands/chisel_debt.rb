# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # `/chisel-debt` — harvest inline `chisel:` deferral markers from the
      # codebase into a ledger view so postponed simplifications aren't lost.
      class ChiselDebt < Base
        def self.command_name = '/chisel-debt'
        def self.description = 'List deferred `chisel:` markers in the codebase'

        def execute(_args, ctx)
          items = RubynCode::Chisel::Debt.scan(ctx.project_root)
          return ctx.renderer.info('No chisel: debt markers found — clean.') if items.empty?

          ctx.renderer.info("Chisel debt — #{items.size} deferred #{pluralize(items.size, 'simplification')}:")
          items.each { |item| ctx.renderer.info("  #{item.file}:#{item.line} — #{item.note}") }
        end

        private

        def pluralize(count, word)
          count == 1 ? word : "#{word}s"
        end
      end
    end
  end
end
