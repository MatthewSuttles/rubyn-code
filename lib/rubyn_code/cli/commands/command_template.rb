# frozen_string_literal: true

require 'open3'

module RubynCode
  module CLI
    module Commands
      # Renders a user-defined slash-command body into a prompt, mirroring
      # Claude Code's command templating:
      #
      #   $ARGUMENTS   → all args, space-joined
      #   $1 .. $9     → positional args
      #   !`shell cmd` → replaced with the command's (combined) output
      #
      # Bash substitution runs the user's own command file, so it carries the
      # same trust as user hooks. Output is captured defensively and capped.
      class CommandTemplate
        BANG = /!`([^`]+)`/
        POSITIONAL = /\$([1-9])/
        MAX_BASH_OUTPUT = 16 * 1024

        def initialize(body)
          @body = body.to_s
        end

        # @param args [Array<String>] arguments passed after the command name
        # @return [String] the rendered prompt
        def render(args = [])
          text = substitute_bash(@body)
          text = text.gsub('$ARGUMENTS', args.join(' '))
          text.gsub(POSITIONAL) { args[Regexp.last_match(1).to_i - 1].to_s }
        end

        private

        def substitute_bash(text)
          text.gsub(BANG) { run(Regexp.last_match(1)) }
        end

        def run(cmd)
          out, = Open3.capture2e(cmd)
          out = "#{out.byteslice(0, MAX_BASH_OUTPUT)}\n… [truncated]" if out.bytesize > MAX_BASH_OUTPUT
          out.strip
        rescue StandardError => e
          "[command failed: #{e.message}]"
        end
      end
    end
  end
end
