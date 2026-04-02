# frozen_string_literal: true

module RubynCode
  module CLI
    class InputHandler
      SLASH_COMMANDS = {
        "/quit" => :quit,
        "/exit" => :quit,
        "/q" => :quit,
        "/compact" => :compact,
        "/cost" => :cost,
        "/clear" => :clear,
        "/undo" => :undo,
        "/help" => :help,
        "/tasks" => :tasks,
        "/budget" => :budget,
        "/resume" => :resume,
        "/skill" => :skill,
        "/version" => :version,
        "/review" => :review,
        "/spawn" => :spawn_teammate
      }.freeze

      Command = Data.define(:action, :args)

      def parse(input)
        return Command.new(action: :quit, args: []) if input.nil?

        stripped = input.strip
        return Command.new(action: :empty, args: []) if stripped.empty?

        if stripped.start_with?("/")
          parse_slash_command(stripped)
        else
          Command.new(action: :message, args: [process_file_references(stripped)])
        end
      end

      def multiline?(line)
        line&.end_with?("\\")
      end

      def strip_continuation(line)
        line.chomp("\\")
      end

      private

      def parse_slash_command(input)
        return Command.new(action: :list_commands, args: []) if input.strip == "/"

        parts = input.split(/\s+/, 2)
        cmd = parts[0].downcase
        args = parts[1]&.split(/\s+/) || []

        action = SLASH_COMMANDS[cmd]

        if action
          Command.new(action: action, args: args)
        else
          Command.new(action: :unknown_command, args: [cmd])
        end
      end

      def process_file_references(input)
        input.gsub(/@(\S+)/) do |match|
          path = Regexp.last_match(1)
          if File.exist?(path)
            content = File.read(path, encoding: "utf-8")
            truncated = content.length > 50_000 ? "#{content[0...50_000]}\n[truncated]" : content
            "\n<file path=\"#{path}\">\n#{truncated}\n</file>\n"
          else
            match
          end
        end
      end
    end
  end
end
