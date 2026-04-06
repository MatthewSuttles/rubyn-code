# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::SpecOutputParser do
  describe '.parse' do
    context 'with nil or empty input' do
      it 'returns "(no output)" for nil' do
        expect(described_class.parse(nil)).to eq('(no output)')
      end

      it 'returns "(no output)" for an empty string' do
        expect(described_class.parse('')).to eq('(no output)')
      end

      it 'returns "(no output)" for whitespace-only input' do
        expect(described_class.parse("   \n  \t  ")).to eq('(no output)')
      end
    end

    context 'with passing RSpec output' do
      it 'returns only the summary line' do
        output = <<~RSPEC
          ......................

          Finished in 1.23 seconds (files took 0.5 seconds to load)
          22 examples, 0 failures
        RSPEC

        result = described_class.parse(output)
        expect(result).to eq('22 examples, 0 failures')
      end

      it 'handles singular example' do
        output = <<~RSPEC
          .

          Finished in 0.01 seconds
          1 example, 0 failures
        RSPEC

        result = described_class.parse(output)
        expect(result).to eq('1 example, 0 failures')
      end
    end

    context 'with failing RSpec output' do
      it 'includes failure details and summary' do
        output = <<~RSPEC
          .F.

          Failures:

            1) Something is broken
               Failure/Error: expect(true).to eq(false)
               expected: false
                    got: true

          Finished in 0.5 seconds
          3 examples, 1 failure
        RSPEC

        result = described_class.parse(output)
        expect(result).to include('1) Something is broken')
        expect(result).to include('expected: false')
        expect(result).to include('3 examples, 1 failure')
      end
    end

    context 'with MAX_FAILURES limit' do
      it 'keeps at most MAX_FAILURES failures' do
        failures = (1..15).map do |i|
          "  #{i}) Test failure number #{i}\n" \
          "     Failure/Error: expect(#{i}).to eq(0)\n" \
          "     expected: 0\n" \
          "          got: #{i}\n\n"
        end

        output = ".F\n\nFailures:\n\n" + failures.join + "\n15 examples, 15 failures\n"

        result = described_class.parse(output)
        expect(result).to include('10) Test failure number 10')
        expect(result).not_to include('11) Test failure number 11')
      end
    end

    context 'with MAX_FAILURE_LINES limit per failure' do
      it 'truncates long failure bodies' do
        long_body = (1..30).map { |i| "    line #{i} of output\n" }.join
        output = <<~RSPEC
          F

          Failures:

            1) Long failure
          #{long_body}
          1 example, 1 failure
        RSPEC

        result = described_class.parse(output)
        lines_in_failure = result.lines.select { |l| l.include?('line') && l.include?('of output') }
        expect(lines_in_failure.size).to be <= described_class::MAX_FAILURE_LINES
      end
    end

    context 'with passing Minitest output' do
      it 'returns only the summary line' do
        output = <<~MINITEST
          # Running:

          ......

          Finished in 0.123456s, 48.6000 runs/s, 48.6000 assertions/s.

          6 runs, 6 assertions, 0 failures, 0 errors, 0 skips
        MINITEST

        result = described_class.parse(output)
        expect(result).to eq('6 runs, 6 assertions, 0 failures, 0 errors, 0 skips')
      end
    end

    context 'with failing Minitest output' do
      it 'includes failure details and summary' do
        output = <<~MINITEST
          # Running:

          .F.

            1) Failure:
          TestSomething#test_it_works [test/something_test.rb:10]:
          Expected: true
            Actual: false

          3 runs, 3 assertions, 1 failures, 0 errors, 0 skips
        MINITEST

        result = described_class.parse(output)
        expect(result).to include('1) Failure:')
        expect(result).to include('Expected: true')
        expect(result).to include('3 runs, 3 assertions, 1 failures')
      end
    end

    context 'with non-test output' do
      it 'passes through unchanged' do
        output = "Hello, this is just regular output\nNothing to see here\n"
        expect(described_class.parse(output)).to eq(output)
      end
    end
  end
end
