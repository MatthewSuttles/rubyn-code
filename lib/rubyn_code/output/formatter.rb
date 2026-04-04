# frozen_string_literal: true

require 'pastel'
require 'rouge'

module RubynCode
  module Output
    class Formatter
      TOOL_ICON = "\u{1F527}"  # wrench
      AGENT_ICON = "\u{1F916}" # robot

      attr_reader :pastel

      def initialize(enabled: $stdout.tty?)
        @pastel = Pastel.new(enabled: enabled)
      end

      def success(message)
        output pastel.green("\u2714 #{message}")
      end

      def error(message)
        output pastel.red("\u2718 #{message}")
      end

      def warning(message)
        output pastel.yellow("\u26A0 #{message}")
      end

      def info(message)
        output pastel.cyan("\u2139 #{message}")
      end

      def dim(message)
        output pastel.dim(message)
      end

      def bold(message)
        output pastel.bold(message)
      end

      def code_block(code, language: 'ruby')
        lexer = find_lexer(language)
        formatter = Rouge::Formatters::Terminal256.new(theme: Rouge::Themes::Monokai.new)

        highlighted = formatter.format(lexer.lex(code))

        lines = [
          pastel.dim("\u2500" * 40),
          highlighted,
          pastel.dim("\u2500" * 40)
        ]

        output lines.join("\n")
      end

      def diff(text)
        lines = text.each_line.map do |line|
          case line
          when /\A\+{3}\s/  then pastel.bold(line)
          when /\A-{3}\s/   then pastel.bold(line)
          when /\A@@/        then pastel.cyan(line)
          when /\A\+/        then pastel.green(line)
          when /\A-/         then pastel.red(line)
          else                    pastel.dim(line)
          end
        end

        output lines.join
      end

      def tool_call(tool_name, arguments = {})
        header = pastel.magenta.bold("#{TOOL_ICON} #{tool_name}")
        parts = [header]

        unless arguments.empty?
          args_display = arguments.map do |key, value|
            display_value = truncate(value.to_s, 120)
            "  #{pastel.dim("#{key}:")} #{display_value}"
          end
          parts.concat(args_display)
        end

        output parts.join("\n")
      end

      def tool_result(tool_name, result, success: true)
        status = success ? pastel.green("\u2714") : pastel.red("\u2718")
        header = pastel.magenta("#{status} #{tool_name}")
        result_text = truncate(result.to_s, 500)

        output "#{header}\n#{pastel.dim(result_text)}"
      end

      def agent_message(message)
        prefix = pastel.blue.bold("#{AGENT_ICON} Assistant")
        output "#{prefix}\n#{message}"
      end

      private

      def output(text)
        $stdout.puts(text)
        text
      end

      def truncate(text, max_length)
        return text if text.length <= max_length

        "#{text[0, max_length]}#{pastel.dim('... (truncated)')}"
      end

      def find_lexer(language)
        Rouge::Lexer.find(language.to_s) || Rouge::Lexers::PlainText.new
      rescue StandardError
        Rouge::Lexers::PlainText.new
      end
    end
  end
end
