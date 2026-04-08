# frozen_string_literal: true

module RubynCode
  module Tools
    # Compresses tool output before it enters the conversation context.
    # Each tool type has a strategy and threshold — outputs below the
    # threshold pass through unchanged; larger outputs are compressed
    # to keep context lean.
    class OutputCompressor
      CHARS_PER_TOKEN = 4

      THRESHOLDS = {
        'run_specs' => { max_tokens: 500, strategy: :spec_summary },
        'bash' => { max_tokens: 1000, strategy: :head_tail },
        'git_log' => { max_tokens: 800, strategy: :head_tail },
        'git_diff' => { max_tokens: 2000, strategy: :relevant_hunks },
        'grep' => { max_tokens: 1000, strategy: :top_matches },
        'glob' => { max_tokens: 500,  strategy: :tree },
        'git_status' => { max_tokens: 500, strategy: :head_tail },
        'read_file' => { max_tokens: 3000, strategy: :head_tail }
      }.freeze

      DEFAULT_THRESHOLD = { max_tokens: 1500, strategy: :head_tail }.freeze

      attr_reader :stats

      def initialize
        @stats = { calls: 0, compressed: 0, tokens_saved: 0 }
      end

      def compress(tool_name, raw_output)
        return raw_output if raw_output.nil? || raw_output.empty?

        @stats[:calls] += 1
        config = THRESHOLDS.fetch(tool_name.to_s, DEFAULT_THRESHOLD)
        max_chars = config[:max_tokens] * CHARS_PER_TOKEN

        return raw_output if raw_output.length <= max_chars

        compressed = apply_strategy(config[:strategy], raw_output, max_chars)
        record_savings(raw_output, compressed)
        compressed
      end

      private

      def apply_strategy(strategy, output, max_chars)
        case strategy
        when :spec_summary   then compress_spec_output(output)
        when :head_tail      then head_tail(output, max_chars)
        when :relevant_hunks then compress_diff(output, max_chars)
        when :top_matches    then top_matches(output, max_chars)
        when :tree           then collapse_tree(output, max_chars)
        end
      end

      def compress_spec_output(output)
        lines = output.lines
        summary_line = find_summary_line(lines)

        return summary_line.strip if summary_line&.include?('0 failures')

        failures = extract_spec_failures(lines)
        return summary_line.strip if failures.empty? && summary_line

        result = assemble_failure_report(failures, summary_line)

        # Guard: if compression produced an empty string (no summary line
        # and no extractable failures), return the original output so the
        # agent still sees spec results.
        result.nil? || result.strip.empty? ? output : result
      end

      def find_summary_line(lines)
        lines.reverse_each.find { |l| l.match?(/\d+ examples?/) }
      end

      def assemble_failure_report(failures, summary_line)
        parts = []
        parts.concat(failures.first(10))
        parts << summary_line.strip if summary_line
        remaining = failures.size - 10
        parts << "(#{remaining} more failures omitted)" if remaining.positive?
        parts.join("\n")
      end

      def extract_spec_failures(lines)
        failures = []
        capturing = false

        lines.each do |line|
          if line.match?(/^\s+\d+\)\s/) || line.match?(%r{^Failure/Error:})
            capturing = true
            failures << +''
          end

          if capturing
            failures.last << line
            capturing = false if line.strip.empty? && failures.last.length > 20
          end
        end

        failures
      end

      # rubocop:disable Metrics/AbcSize -- head/tail splitting requires coordinated arithmetic
      def head_tail(output, max_chars)
        lines = output.lines
        return output if lines.size <= 10

        head_chars = (max_chars * 0.6).to_i
        tail_chars = (max_chars * 0.3).to_i

        head_lines = take_lines_up_to(lines, head_chars)
        tail_lines = take_lines_up_to(lines.reverse, tail_chars).reverse
        omitted = lines.size - head_lines.size - tail_lines.size

        parts = [head_lines.join]
        parts << "\n... [#{omitted} lines omitted] ...\n" if omitted.positive?
        parts << tail_lines.join
        parts.join
      end
      # rubocop:enable Metrics/AbcSize

      # rubocop:disable Metrics/AbcSize -- diff hunk iteration with header extraction
      def compress_diff(output, max_chars)
        hunks = output.split(/^(?=diff --git)/)
        return head_tail(output, max_chars) if hunks.size <= 1

        result = +''
        hunks.each do |hunk|
          header = hunk.lines.first(4).join
          if result.length + hunk.length <= max_chars
            result << hunk
          else
            result << header
            result << "  ... (#{hunk.lines.size - 4} lines in this file omitted)\n"
          end
        end

        result
      end
      # rubocop:enable Metrics/AbcSize

      def top_matches(output, max_chars)
        lines = output.lines
        kept = take_lines_up_to(lines, max_chars)
        omitted = lines.size - kept.size

        result = kept.join
        result << "\n... (#{omitted} more matches omitted)\n" if omitted.positive?
        result
      end

      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity -- multi-step tree collapse
      def collapse_tree(output, max_chars)
        paths = output.lines.map(&:strip).reject(&:empty?)
        return output if output.length <= max_chars

        dirs = paths.map { |p| File.dirname(p) }.tally.sort_by { |_, c| -c }
        result = dirs.map { |dir, count| "#{dir}/ (#{count} files)" }.join("\n")

        return result if result.length <= max_chars

        head_tail(result, max_chars)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

      def take_lines_up_to(lines, max_chars)
        taken = []
        total = 0
        lines.each do |line|
          break if total + line.length > max_chars

          taken << line
          total += line.length
        end
        taken
      end

      def record_savings(original, compressed)
        saved = (original.length - compressed.length) / CHARS_PER_TOKEN
        return unless saved.positive?

        @stats[:compressed] += 1
        @stats[:tokens_saved] += saved
      end
    end
  end
end
