# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Diff < Base
        def self.command_name = '/diff'
        def self.description = 'Show git diff (staged, unstaged, or vs branch)'

        def execute(args, ctx)
          target = args.first || 'unstaged'

          cmd = case target
                when 'staged'   then 'git diff --cached'
                when 'unstaged' then 'git diff'
                else "git diff #{target}...HEAD"
                end

          output = `cd #{ctx.project_root} && #{cmd} 2>&1`

          if output.strip.empty?
            ctx.renderer.info("No changes (#{target}).")
          else
            puts output
          end
        end
      end
    end
  end
end
