# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      # `/chisel-review` — audit the current branch's changes for
      # over-engineering and report a ranked deletion list. Read-only.
      class ChiselReview < Base
        def self.command_name = '/chisel-review'
        def self.description = 'Find over-engineering in the current diff (/chisel-review [base])'

        def execute(args, ctx)
          base = args.fetch(0, 'main')
          ctx.send_message(RubynCode::Chisel::Inspection.prompt(scope: :diff, target: base))
        end
      end
    end
  end
end
