# frozen_string_literal: true

module RubynCode
  module CLI
    class InputHandler
      # Legacy mapping for backward compatibility when no registry is provided.
      # New code should use the command registry instead.
      SLASH_COMMANDS = {
        '/quit' => :quit,
        '/exit' => :quit,
        '/q' => :quit
      }.freeze

      Command = Data.define(:action, :args)

      # @param command_registry [CLI::Commands::Registry, nil]
      def initialize(command_registry: nil)
        @command_registry = command_registry
      end

      def parse(input)
        return Command.new(action: :quit, args: []) if input.nil?

        stripped = input.strip
        return Command.new(action: :empty, args: []) if stripped.empty?

        if stripped.start_with?('/')
          parse_slash_command(stripped)
        else
          Command.new(action: :message, args: [process_file_references(stripped)])
        end
      end

      def multiline?(line)
        line&.end_with?('\\')
      end

      def strip_continuation(line)
        line.chomp('\\')
      end

      private

      def parse_slash_command(input)
        return Command.new(action: :list_commands, args: []) if input.strip == '/'

        parts = input.split(/\s+/, 2)
        cmd = parts[0].downcase
        args = parts[1]&.split(/\s+/) || []

        # Quick exit for /quit and friends
        return Command.new(action: :quit, args: []) if SLASH_COMMANDS[cmd] == :quit

        # Dispatch through registry if available
        if @command_registry&.known?(cmd)
          Command.new(action: :slash_command, args: [cmd, *args])
        else
          Command.new(action: :unknown_command, args: [cmd])
        end
      end

      def process_file_references(input)
        input.gsub(/@(\S+)/) do |match|
          path = Regexp.last_match(1)
          if File.exist?(path)
            content = File.read(path, encoding: 'utf-8')
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
