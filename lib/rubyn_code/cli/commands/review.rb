# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Review < Base
        def self.command_name = '/review'
        def self.description = 'Review current branch against best practices'

        def execute(args, ctx)
          base = args.fetch(0, 'main')
          focus = args.fetch(1, 'all')

          ctx.send_message(build_prompt(base, focus))
        end

        private

        def build_prompt(base, focus)
          "Use the review_pr tool to review my current branch against #{base}. " \
            "Focus: #{focus}. Load relevant best practice skills for any issues you find."
        end
      end
    end
  end
end
