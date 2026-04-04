# frozen_string_literal: true

require 'pastel'
require 'rouge'

module RubynCode
  module CLI
    class Renderer
      def initialize
        @pastel = Pastel.new
        @rouge_formatter = Rouge::Formatters::Terminal256.new(theme: Rouge::Themes::Monokai.new)
      end

      attr_writer :yolo

      def display(response)
        return if response.nil?

        text = case response
               when String then response
               when ->(r) { r.respond_to?(:text) } then response.text
               else response.to_s
               end

        return if text.nil? || text.strip.empty?

        puts
        puts render_markdown(text)
        puts
      end

      def tool_call(name, params)
        puts @pastel.cyan("  > #{name}: #{format_params(params)}")
      end

      def tool_result(_name, output)
        truncated = output.to_s[0...300]
        lines = truncated.lines
        if lines.length > 6
          puts @pastel.dim("    #{lines[0..4].map(&:strip).join("\n    ")}")
          puts @pastel.dim("    ... (#{lines.length - 5} more lines)")
        else
          puts @pastel.dim("    #{truncated.strip.gsub("\n", "\n    ")}")
        end
      end

      def agent_message(name, text)
        puts @pastel.bold.magenta("[#{name}]") + " #{text}"
      end

      def system_message(text)
        puts @pastel.dim.italic(text)
      end

      def success(text)
        puts @pastel.green(text)
      end

      def error(text)
        puts @pastel.red(text)
      end

      def warning(text)
        puts @pastel.yellow(text)
      end

      def info(text)
        puts @pastel.blue(text)
      end

      def welcome
        puts @pastel.bold.cyan('╔══════════════════════════════════════╗')
        puts @pastel.bold.cyan("║         Rubyn Code v#{RubynCode::VERSION}            ║")
        puts @pastel.bold.cyan('║  Ruby & Rails Agentic Assistant      ║')
        puts @pastel.bold.cyan('╚══════════════════════════════════════╝')
        puts
        puts @pastel.dim('Type /help for commands, /quit to exit')
        puts
      end

      def cost_summary(session_cost:, daily_cost:, tokens:)
        puts @pastel.bold('Cost Summary:')
        puts "  Session: $#{'%.4f' % session_cost}"
        puts "  Today:   $#{'%.4f' % daily_cost}"
        puts "  Tokens:  #{tokens[:input]} in / #{tokens[:output]} out"
      end

      def prompt
        if @yolo
          @pastel.bold.green('rubyn ') + @pastel.bold.red('YOLO') + @pastel.bold.green(' > ')
        else
          @pastel.bold.green('rubyn > ')
        end
      end

      private

      def render_markdown(text)
        lines = text.lines
        result = []

        in_code_block = false
        code_lang = nil
        code_buffer = []

        lines.each do |line|
          if line.strip.match?(/\A```(\w*)/)
            if in_code_block
              result << render_code_block(code_buffer.join, code_lang)
              code_buffer = []
              in_code_block = false
              code_lang = nil
            else
              in_code_block = true
              code_lang = line.strip.match(/\A```(\w*)/)[1]
              code_lang = 'ruby' if code_lang.empty?
            end
          elsif in_code_block
            code_buffer << line
          else
            result << render_line(line)
          end
        end

        # Flush any unclosed code block
        result << render_code_block(code_buffer.join, code_lang || 'ruby') unless code_buffer.empty?

        result.join
      end

      def render_code_block(code, lang)
        lexer = Rouge::Lexer.find(lang) || Rouge::Lexers::PlainText.new
        highlighted = @rouge_formatter.format(lexer.lex(code))
        border = @pastel.dim('  │ ')
        formatted = highlighted.lines.map { |l| "#{border}#{l}" }.join
        "\n#{@pastel.dim("  ┌─ #{lang}")}\n#{formatted}#{@pastel.dim('  └─')}\n"
      rescue StandardError
        "\n#{code}\n"
      end

      def render_line(line)
        # Headers
        if line.match?(/\A\s*\#{1,6}\s/)
          level = line.match(/\A\s*(\#{1,6})\s/)[1].length
          text = line.sub(/\A\s*\#{1,6}\s+/, '').rstrip
          case level
          when 1 then "#{@pastel.bold.underline(text)}\n"
          when 2 then "#{@pastel.bold(text)}\n"
          else "#{@pastel.bold(text)}\n"
          end
        # Bullet lists
        elsif line.match?(/\A\s*[-*]\s/)
          indent = line.match(/\A(\s*)/)[1]
          content = line.sub(/\A\s*[-*]\s+/, '')
          "#{indent}  #{@pastel.cyan('•')} #{render_inline(content)}"
        # Numbered lists
        elsif line.match?(/\A\s*\d+\.\s/)
          indent = line.match(/\A(\s*)/)[1]
          num = line.match(/(\d+)\./)[1]
          content = line.sub(/\A\s*\d+\.\s+/, '')
          "#{indent}  #{@pastel.cyan("#{num}.")} #{render_inline(content)}"
        # Horizontal rules
        elsif line.strip.match?(/\A-{3,}\z/)
          "#{@pastel.dim('─' * [terminal_width - 4, 40].min)}\n"
        # Table rows
        elsif line.include?('|')
          render_table_row(line)
        else
          render_inline(line)
        end
      end

      def render_inline(text)
        text
          .gsub(/\*\*(.+?)\*\*/) { @pastel.bold(Regexp.last_match(1)) }
          .gsub(/\*(.+?)\*/) { @pastel.italic(Regexp.last_match(1)) }
          .gsub(/`([^`]+)`/) { @pastel.cyan(Regexp.last_match(1)) }
      end

      def render_table_row(line)
        return '' if line.strip.match?(/\A\|[\s\-:|]+\|\z/) # separator row

        cells = line.split('|').map(&:strip).reject(&:empty?)
        "  #{cells.map { |c| render_inline(c) }.join('  │  ')}\n"
      end

      def format_params(params)
        case params
        when Hash
          params.map { |k, v| "#{k}=#{v.to_s[0...80]}" }.join(', ')
        else
          params.to_s[0...200]
        end
      end

      def terminal_width
        IO.console&.winsize&.last || 120
      rescue StandardError
        120
      end
    end
  end
end
