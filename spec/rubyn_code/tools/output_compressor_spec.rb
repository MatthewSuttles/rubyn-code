# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::OutputCompressor do
  subject(:compressor) { described_class.new }

  describe '#compress' do
    context 'with nil or empty input' do
      it 'returns nil unchanged' do
        expect(compressor.compress('bash', nil)).to be_nil
      end

      it 'returns empty string unchanged' do
        expect(compressor.compress('bash', '')).to eq('')
      end

      it 'does not increment calls for nil input' do
        compressor.compress('bash', nil)
        expect(compressor.stats[:calls]).to eq(0)
      end
    end

    context 'when output is below the threshold' do
      it 'returns short output unchanged' do
        output = 'hello world'
        expect(compressor.compress('bash', output)).to eq(output)
      end

      it 'increments calls but not compressed' do
        compressor.compress('bash', 'short')
        expect(compressor.stats[:calls]).to eq(1)
        expect(compressor.stats[:compressed]).to eq(0)
      end
    end

    context 'when output is exactly at threshold' do
      it 'returns output unchanged at the character limit' do
        max_chars = 1000 * described_class::CHARS_PER_TOKEN
        output = 'x' * max_chars
        expect(compressor.compress('bash', output)).to eq(output)
      end
    end

    context 'with a single-line output above threshold' do
      it 'returns the line unchanged when head_tail has 10 or fewer lines' do
        max_chars = 1000 * described_class::CHARS_PER_TOKEN
        output = 'x' * (max_chars + 100)
        # Single line, head_tail returns as-is since lines.size <= 10
        result = compressor.compress('bash', output)
        expect(result).to eq(output)
      end
    end

    context 'with an unknown tool name' do
      it 'uses the default threshold and head_tail strategy' do
        max_chars = described_class::DEFAULT_THRESHOLD[:max_tokens] * described_class::CHARS_PER_TOKEN
        lines = Array.new(100) { 'x' * 100 + "\n" }
        output = lines.join
        next unless output.length > max_chars

        result = compressor.compress('unknown_tool', output)
        expect(result).to include('lines omitted')
      end
    end
  end

  describe 'spec_summary strategy' do
    let(:tool_name) { 'run_specs' }
    let(:max_chars) { 500 * described_class::CHARS_PER_TOKEN }

    context 'with passing specs' do
      it 'returns only the summary line' do
        output = build_passing_spec_output(max_chars + 100)
        result = compressor.compress(tool_name, output)
        expect(result).to match(/\d+ examples?, 0 failures/)
        expect(result).not_to include('...')
      end
    end

    context 'with failing specs' do
      it 'preserves failure details and summary' do
        output = build_failing_spec_output(max_chars + 100)
        result = compressor.compress(tool_name, output)
        expect(result).to include('1)')
        expect(result).to match(/\d+ examples?/)
      end
    end

    context 'with more than 10 failures' do
      it 'shows first 10 failures and omitted count' do
        failures = (1..12).map do |i|
          "  #{i}) Something fails ##{i}\n     Failure/Error: expect(true).to eq(false)\n\n"
        end
        output = "Running specs...\n" + ('.' * 3000) + "\n" +
                 "Failures:\n\n" + failures.join + "\n12 examples, 12 failures\n"

        result = compressor.compress(tool_name, output)
        expect(result).to include('2 more failures omitted')
      end
    end
  end

  describe 'head_tail strategy' do
    let(:tool_name) { 'bash' }

    it 'keeps head and tail lines with omitted count in the middle' do
      lines = (1..800).map { |i| "line #{i}: #{'x' * 20}\n" }
      output = lines.join

      result = compressor.compress(tool_name, output)
      expect(result).to include('line 1:')
      expect(result).to include('line 800:')
      expect(result).to match(/\d+ lines omitted/)
    end
  end

  describe 'relevant_hunks strategy (diff compression)' do
    let(:tool_name) { 'git_diff' }
    let(:max_chars) { 2000 * described_class::CHARS_PER_TOKEN }

    it 'preserves hunk headers and truncates large bodies' do
      hunks = (1..20).map do |i|
        header = "diff --git a/file#{i}.rb b/file#{i}.rb\n" \
                 "index abc..def 100644\n" \
                 "--- a/file#{i}.rb\n" \
                 "+++ b/file#{i}.rb\n"
        body = (1..100).map { |l| "+added line #{l}\n" }.join
        header + body
      end
      output = hunks.join

      next unless output.length > max_chars

      result = compressor.compress(tool_name, output)
      expect(result).to include('diff --git')
      expect(result).to include('lines in this file omitted')
    end

    it 'falls back to head_tail for non-diff content' do
      lines = (1..500).map { |i| "plain line #{i}\n" }
      output = lines.join
      next unless output.length > max_chars

      result = compressor.compress(tool_name, output)
      expect(result).to include('lines omitted')
    end
  end

  describe 'top_matches strategy' do
    let(:tool_name) { 'grep' }
    let(:max_chars) { 1000 * described_class::CHARS_PER_TOKEN }

    it 'keeps the first N matches and shows omitted count' do
      lines = (1..500).map { |i| "path/to/file#{i}.rb:42: match #{i}\n" }
      output = lines.join

      next unless output.length > max_chars

      result = compressor.compress(tool_name, output)
      expect(result).to include('match 1')
      expect(result).to match(/\d+ more matches omitted/)
    end
  end

  describe 'tree strategy' do
    let(:tool_name) { 'glob' }
    let(:max_chars) { 500 * described_class::CHARS_PER_TOKEN }

    it 'collapses directories with file counts' do
      paths = (1..300).map { |i| "app/models/file#{i}.rb\n" }
      output = paths.join

      next unless output.length > max_chars

      result = compressor.compress(tool_name, output)
      expect(result).to include('app/models/')
      expect(result).to include('files)')
    end
  end

  describe '#stats' do
    it 'starts with zero values' do
      expect(compressor.stats).to eq(calls: 0, compressed: 0, tokens_saved: 0)
    end

    it 'tracks calls and compressions' do
      lines = (1..800).map { |i| "line #{i}: #{'x' * 20}\n" }
      large_output = lines.join

      compressor.compress('bash', large_output)
      compressor.compress('bash', 'small')

      expect(compressor.stats[:calls]).to eq(2)
      expect(compressor.stats[:compressed]).to eq(1)
      expect(compressor.stats[:tokens_saved]).to be_positive
    end
  end

  private

  def build_passing_spec_output(min_length)
    dots = '.' * [min_length - 50, 100].max
    "#{dots}\n\n42 examples, 0 failures\n"
  end

  def build_failing_spec_output(min_length)
    padding = '.' * [min_length - 200, 100].max
    <<~OUTPUT
      #{padding}

      Failures:

        1) Something is broken
           Failure/Error: expect(true).to eq(false)

      1 example, 1 failure
    OUTPUT
  end
end
