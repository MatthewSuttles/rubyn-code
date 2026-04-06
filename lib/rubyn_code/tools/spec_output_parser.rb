# frozen_string_literal: true

module RubynCode
  module Tools
    # Parses raw test framework output (RSpec/Minitest) into compact summaries.
    # Passing suites compress to a single line; failures preserve enough context
    # to diagnose the issue without the full verbose output.
    module SpecOutputParser
      MAX_FAILURE_LINES = 15
      MAX_FAILURES = 10

      class << self
        # Parse raw spec output into a compact summary.
        #
        # @param raw [String] raw test framework output
        # @return [String] compressed summary
        def parse(raw)
          return '(no output)' if raw.nil? || raw.strip.empty?

          if rspec_output?(raw)
            parse_rspec(raw)
          elsif minitest_output?(raw)
            parse_minitest(raw)
          else
            raw
          end
        end

        private

        def rspec_output?(raw)
          raw.include?('example') && (raw.include?('failure') || raw.include?('pending'))
        end

        def minitest_output?(raw)
          raw.include?('assertions') || raw.include?('runs,')
        end

        def parse_rspec(raw)
          summary = extract_rspec_summary(raw)
          return summary if summary && !raw.include?('FAILED') && raw.match?(/0 failures/)

          failures = extract_rspec_failures(raw)
          parts = []
          parts.concat(format_failures(failures))
          parts << summary if summary
          parts.empty? ? raw : parts.join("\n")
        end

        def extract_rspec_summary(raw)
          raw.lines.reverse_each do |line|
            return line.strip if line.match?(/\d+ examples?.*\d+ failures?/)
          end
          nil
        end

        def extract_rspec_failures(raw)
          failures = []
          current = nil

          raw.each_line do |line|
            if line.match?(/^\s+\d+\)\s/)
              failures << current if current
              current = { header: line.strip, body: [] }
            elsif current
              current[:body] << line.rstrip if current[:body].size < MAX_FAILURE_LINES
            end
          end

          failures << current if current
          failures.first(MAX_FAILURES)
        end

        def parse_minitest(raw)
          summary = extract_minitest_summary(raw)
          return summary if summary && raw.match?(/0 failures/)

          failures = extract_minitest_failures(raw)
          parts = []
          parts.concat(format_failures(failures))
          parts << summary if summary
          parts.empty? ? raw : parts.join("\n")
        end

        def extract_minitest_summary(raw)
          raw.lines.reverse_each do |line|
            return line.strip if line.match?(/\d+ runs?,\s*\d+ assertions?/)
          end
          nil
        end

        def extract_minitest_failures(raw)
          failures = []
          current = nil

          raw.each_line do |line|
            if line.match?(/^\s+\d+\)\s(Failure|Error):/)
              failures << current if current
              current = { header: line.strip, body: [] }
            elsif current
              current[:body] << line.rstrip if current[:body].size < MAX_FAILURE_LINES
            end
          end

          failures << current if current
          failures.first(MAX_FAILURES)
        end

        def format_failures(failures)
          failures.map do |f|
            body = f[:body].reject(&:empty?).first(MAX_FAILURE_LINES)
            "#{f[:header]}\n#{body.join("\n")}"
          end
        end
      end
    end
  end
end
