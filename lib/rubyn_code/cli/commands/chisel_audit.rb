# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # `/chisel-audit` — sweep the repo (or a path) for accumulated
      # over-engineering and report a ranked deletion list. Read-only.
      class ChiselAudit < Base
        def self.command_name = '/chisel-audit'
        def self.description = 'Find over-engineering across the repo (/chisel-audit [path])'

        def execute(args, ctx)
          path = args.first
          ctx.send_message(RubynCode::Chisel::Inspection.prompt(scope: :repo, target: path))
        end
      end
    end
  end
end
