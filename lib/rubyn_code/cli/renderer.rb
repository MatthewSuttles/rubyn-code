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

      DIFF_TOOLS = %w[edit_file write_file].freeze
      DIFF_RESULT_LIMIT = 2000
      DEFAULT_RESULT_LIMIT = 500

      def tool_result(name, output)
        raw = output.to_s

        if DIFF_TOOLS.include?(name.to_s)
          render_diff_result(raw[0...DIFF_RESULT_LIMIT].lines)
        else
          truncated = raw[0...DEFAULT_RESULT_LIMIT]
          lines = truncated.lines
          if lines.length > 6
            render_truncated_result(lines)
          else
            puts @pastel.dim("    #{truncated.strip.gsub("\n", "\n    ")}")
          end
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
        puts format('  Session: $%.4f', session_cost)
        puts format('  Today:   $%.4f', daily_cost)
        puts "  Tokens:  #{tokens[:input]} in / #{tokens[:output]} out"
      end

      def prompt
        return @pastel.bold.green('rubyn ') + @pastel.bold.red('YOLO') + @pastel.bold.green(' > ') if @yolo

        @pastel.bold.green('rubyn > ')
      end

      DIFF_COLORS = {
        /\A  \+ / => :green,
        /\A  - / => :red,
        /\A  @@ / => :cyan,
        /\A(?:Created|Updated|Edited) / => :yellow
      }.freeze

      private

      def render_diff_result(lines)
        lines.each do |line|
          stripped = line.rstrip
          puts "    #{colorize_diff_line(stripped)}"
        end
      end

      def colorize_diff_line(line)
        DIFF_COLORS.each do |pattern, color|
          return @pastel.decorate(line, color) if line.match?(pattern)
        end
        @pastel.dim(line)
      end

      def render_truncated_result(lines)
        puts @pastel.dim("    #{lines[0..4].map(&:strip).join("\n    ")}")
        puts @pastel.dim("    ... (#{lines.length - 5} more lines)")
      end

      def render_markdown(text)
        lines = text.lines
        result = []
        in_code_block = false
        code_lang = nil
        code_buffer = []

        lines.each do |line|
          in_code_block, code_lang, code_buffer = process_markdown_line(
            line, in_code_block, code_lang, code_buffer, result
          )
        end

        # Flush any unclosed code block
        flush_code_buffer(code_buffer, code_lang, result)

        result.join
      end

      def process_markdown_line(line, in_code_block, code_lang, code_buffer, result)
        if line.strip.match?(/\A```(\w*)/)
          handle_code_fence(line, in_code_block, code_lang, code_buffer, result)
        elsif in_code_block
          code_buffer << line
          [in_code_block, code_lang, code_buffer]
        else
          result << render_line(line)
          [in_code_block, code_lang, code_buffer]
        end
      end

      def handle_code_fence(line, in_code_block, code_lang, code_buffer, result)
        if in_code_block
          result << render_code_block(code_buffer.join, code_lang)
          [false, nil, []]
        else
          lang = line.strip.match(/\A```(\w*)/)[1]
          lang = 'ruby' if lang.empty?
          [true, lang, []]
        end
      end

      def flush_code_buffer(code_buffer, code_lang, result)
        return if code_buffer.empty?

        result << render_code_block(code_buffer.join, code_lang || 'ruby')
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
        case line
        when /\A\s*\#{1,6}\s/   then render_header(line)
        when /\A\s*[-*]\s/      then render_bullet(line)
        when /\A\s*\d+\.\s/     then render_numbered_item(line)
        when ->(l) { l.strip.match?(/\A-{3,}\z/) } then "#{@pastel.dim('─' * [terminal_width - 4, 40].min)}\n"
        when /\|/ then render_table_row(line)
        else render_inline(line)
        end
      end

      def render_header(line)
        level = line.match(/\A\s*(\#{1,6})\s/)[1].length
        text = line.sub(/\A\s*\#{1,6}\s+/, '').rstrip
        case level
        when 1 then "#{@pastel.bold.underline(text)}\n"
        else "#{@pastel.bold(text)}\n"
        end
      end

      def render_bullet(line)
        indent = line.match(/\A(\s*)/)[1]
        content = line.sub(/\A\s*[-*]\s+/, '')
        "#{indent}  #{@pastel.cyan('•')} #{render_inline(content)}"
      end

      def render_numbered_item(line)
        indent = line.match(/\A(\s*)/)[1]
        num = line.match(/(\d+)\./)[1]
        content = line.sub(/\A\s*\d+\.\s+/, '')
        "#{indent}  #{@pastel.cyan("#{num}.")} #{render_inline(content)}"
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
