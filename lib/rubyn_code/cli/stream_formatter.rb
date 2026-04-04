# frozen_string_literal: true

require 'pastel'
require 'rouge'

module RubynCode
  module CLI
    # Formats streamed text on-the-fly with markdown rendering.
    # Buffers code blocks until they close, then syntax-highlights them.
    # Applies inline formatting (bold, code, headers) as text arrives.
    class StreamFormatter
      def initialize(_renderer = nil)
        @pastel = Pastel.new
        @rouge_formatter = Rouge::Formatters::Terminal256.new(theme: Rouge::Themes::Monokai.new)
        @buffer = +''
        @in_code_block = false
        @code_lang = nil
        @code_buffer = +''
      end

      # Feed a chunk of streamed text
      def feed(text)
        @buffer << text

        # Process complete lines from the buffer
        while (newline_idx = @buffer.index("\n"))
          line = @buffer.slice!(0, newline_idx + 1)
          process_line(line)
        end

        # Print any remaining partial line (no newline yet) if not in a code block
        return if @in_code_block || @buffer.empty?

        $stdout.print format_inline(@buffer)
        $stdout.flush
        @buffer = +''
      end

      # Flush any remaining buffered content
      def flush
        unless @buffer.empty?
          if @in_code_block
            @code_buffer << @buffer
            render_code_block
          else
            $stdout.print format_inline(@buffer)
          end
          @buffer = +''
        end

        # Flush unclosed code block
        render_code_block if @in_code_block && !@code_buffer.empty?
        $stdout.flush
      end

      private

      def process_line(line)
        stripped = line.rstrip

        # Code block toggle
        if stripped.match?(/\A\s*```/)
          if @in_code_block
            # Closing fence — render the buffered code
            render_code_block
            @in_code_block = false
            @code_lang = nil
          else
            # Opening fence
            @in_code_block = true
            @code_lang = stripped.match(/```(\w*)/)[1]
            @code_lang = 'ruby' if @code_lang.empty?
            @code_buffer = +''
            $stdout.puts @pastel.dim("  ┌─ #{@code_lang}")
          end
          return
        end

        if @in_code_block
          @code_buffer << line
          return
        end

        # Regular line — format and print
        $stdout.print format_line(line)
        $stdout.flush
      end

      def render_code_block
        return if @code_buffer.empty?

        lexer = Rouge::Lexer.find(@code_lang || 'ruby') || Rouge::Lexers::PlainText.new
        highlighted = @rouge_formatter.format(lexer.lex(@code_buffer))
        border = @pastel.dim('  │ ')

        highlighted.each_line do |l|
          $stdout.print "#{border}#{l}"
        end
        $stdout.puts @pastel.dim('  └─')
        $stdout.flush

        @code_buffer = +''
      rescue StandardError
        # Fallback: print unformatted
        @code_buffer.each_line { |l| $stdout.print "  #{l}" }
        $stdout.puts
        @code_buffer = +''
      end

      def format_line(line)
        stripped = line.rstrip

        # Headers
        case stripped
        when /\A\#{1,6}\s/
          level = stripped.match(/\A(\#{1,6})\s/)[1].length
          text = stripped.sub(/\A\#{1,6}\s+/, '')
          case level
          when 1 then "#{@pastel.bold.underline(text)}\n"
          when 2 then "\n#{@pastel.bold(text)}\n"
          else "#{@pastel.bold(text)}\n"
          end
        # Bullet lists
        when /\A\s*[-*]\s/
          indent = stripped.match(/\A(\s*)/)[1]
          content = stripped.sub(/\A\s*[-*]\s+/, '')
          "#{indent}  #{@pastel.cyan('•')} #{format_inline(content)}\n"
        # Numbered lists
        when /\A\s*\d+\.\s/
          indent = stripped.match(/\A(\s*)/)[1]
          num = stripped.match(/(\d+)\./)[1]
          content = stripped.sub(/\A\s*\d+\.\s+/, '')
          "#{indent}  #{@pastel.cyan("#{num}.")} #{format_inline(content)}\n"
        # Horizontal rules
        when /\A-{3,}\z/
          "#{@pastel.dim('─' * 40)}\n"
        else
          "#{format_inline(line.chomp)}\n"
        end
      end

      def format_inline(text)
        text
          .gsub(/\*\*(.+?)\*\*/) { @pastel.bold(Regexp.last_match(1)) }
          .gsub(/(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)/) { @pastel.italic(Regexp.last_match(1)) }
          .gsub(/`([^`]+)`/) { @pastel.cyan(Regexp.last_match(1)) }
      end
    end
  end
end
