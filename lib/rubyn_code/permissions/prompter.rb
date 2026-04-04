# frozen_string_literal: true

require 'tty-prompt'
require 'pastel'
require 'json'

module RubynCode
  module Permissions
    module Prompter
      # Ask the user to confirm a regular tool invocation.
      #
      # @param tool_name [String]
      # @param tool_input [Hash]
      # @return [Boolean] true if the user approved
      def self.confirm(tool_name, tool_input)
        prompt = build_prompt
        pastel = Pastel.new

        display_tool_summary(pastel, tool_name, tool_input)

        prompt.yes?(
          pastel.yellow('Allow this tool call?'),
          default: true
        )
      rescue TTY::Prompt::Reader::InputInterrupt
        false
      end

      # Ask the user to confirm a destructive tool invocation.
      # Requires the user to type "yes" explicitly rather than just pressing Enter.
      #
      # @param tool_name [String]
      # @param tool_input [Hash]
      # @return [Boolean] true if the user approved
      def self.confirm_destructive(tool_name, tool_input)
        prompt = build_prompt
        pastel = Pastel.new

        $stdout.puts pastel.red.bold('WARNING: Destructive operation requested')
        $stdout.puts pastel.red('=' * 50)
        display_tool_summary(pastel, tool_name, tool_input)
        $stdout.puts pastel.red('=' * 50)

        answer = prompt.ask(
          pastel.red.bold('Type "yes" to confirm this destructive action:')
        )

        answer&.strip&.downcase == 'yes'
      rescue TTY::Prompt::Reader::InputInterrupt
        false
      end

      # @api private
      def self.build_prompt
        TTY::Prompt.new(interrupt: :noop)
      end

      # @api private
      def self.display_tool_summary(pastel, tool_name, tool_input)
        $stdout.puts pastel.magenta.bold("Tool: #{tool_name}")

        return if tool_input.nil? || tool_input.empty?

        tool_input.each do |key, value|
          display_value = truncate_value(value.to_s, 200)
          $stdout.puts "  #{pastel.dim("#{key}:")} #{display_value}"
        end
      end

      # @api private
      def self.truncate_value(text, max_length)
        return text if text.length <= max_length

        "#{text[0, max_length]}... (truncated)"
      end

      private_class_method :build_prompt, :display_tool_summary, :truncate_value
    end
  end
end
