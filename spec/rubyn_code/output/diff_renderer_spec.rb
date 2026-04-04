# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Output::DiffRenderer do
  subject(:renderer) { described_class.new(enabled: false, context_lines: context_lines) }

  let(:context_lines) { 3 }

  before { allow($stdout).to receive(:puts) }

  describe 'DiffLine' do
    describe '#addition?' do
      it 'returns true for :add type' do
        line = described_class::DiffLine.new(type: :add, content: 'hello')
        expect(line.addition?).to be true
      end

      it 'returns false for :delete type' do
        line = described_class::DiffLine.new(type: :delete, content: 'hello')
        expect(line.addition?).to be false
      end

      it 'returns false for :context type' do
        line = described_class::DiffLine.new(type: :context, content: 'hello')
        expect(line.addition?).to be false
      end
    end

    describe '#deletion?' do
      it 'returns true for :delete type' do
        line = described_class::DiffLine.new(type: :delete, content: 'hello')
        expect(line.deletion?).to be true
      end

      it 'returns false for :add type' do
        line = described_class::DiffLine.new(type: :add, content: 'hello')
        expect(line.deletion?).to be false
      end

      it 'returns false for :context type' do
        line = described_class::DiffLine.new(type: :context, content: 'hello')
        expect(line.deletion?).to be false
      end
    end

    describe '#context?' do
      it 'returns true for :context type' do
        line = described_class::DiffLine.new(type: :context, content: 'hello')
        expect(line.context?).to be true
      end

      it 'returns false for :add type' do
        line = described_class::DiffLine.new(type: :add, content: 'hello')
        expect(line.context?).to be false
      end

      it 'returns false for :delete type' do
        line = described_class::DiffLine.new(type: :delete, content: 'hello')
        expect(line.context?).to be false
      end
    end
  end

  describe 'Hunk' do
    it 'is a Data value object with the expected members' do
      hunk = described_class::Hunk.new(
        old_start: 1,
        old_count: 3,
        new_start: 1,
        new_count: 4,
        lines: []
      )

      expect(hunk.old_start).to eq(1)
      expect(hunk.old_count).to eq(3)
      expect(hunk.new_start).to eq(1)
      expect(hunk.new_count).to eq(4)
      expect(hunk.lines).to eq([])
    end

    it 'is immutable' do
      hunk = described_class::Hunk.new(
        old_start: 1, old_count: 1, new_start: 1, new_count: 1, lines: []
      )

      expect { hunk.old_start = 5 }.to raise_error(NoMethodError)
    end
  end

  describe '#render' do
    context 'with identical texts' do
      it 'returns "No differences found."' do
        text = "line one\nline two\nline three\n"
        result = renderer.render(text, text)

        expect(result).to eq('No differences found.')
      end

      it 'does not output to $stdout' do
        text = "same\n"
        renderer.render(text, text)

        expect($stdout).not_to have_received(:puts)
      end
    end

    context 'with a simple single-line addition' do
      it 'includes the added line prefixed with +' do
        old_text = "alpha\ngamma\n"
        new_text = "alpha\nbeta\ngamma\n"
        result = renderer.render(old_text, new_text)

        expect(result).to include('+beta')
      end

      it 'does not include any deleted lines' do
        old_text = "alpha\ngamma\n"
        new_text = "alpha\nbeta\ngamma\n"
        result = renderer.render(old_text, new_text)

        diff_body = result.lines.reject { |l| l.start_with?('---', '+++', '@@') }
        expect(diff_body.any? { |l| l.start_with?('-') }).to be false
      end
    end

    context 'with a single-line deletion' do
      it 'includes the removed line prefixed with -' do
        old_text = "alpha\nbeta\ngamma\n"
        new_text = "alpha\ngamma\n"
        result = renderer.render(old_text, new_text)

        expect(result).to include('-beta')
      end

      it 'does not include any added lines' do
        old_text = "alpha\nbeta\ngamma\n"
        new_text = "alpha\ngamma\n"
        result = renderer.render(old_text, new_text)

        diff_body = result.lines.reject { |l| l.start_with?('---', '+++', '@@') }
        expect(diff_body.any? { |l| l.start_with?('+') }).to be false
      end
    end

    context 'with a modification (line changed)' do
      it 'includes both the deleted old line and the added new line' do
        old_text = "alpha\nbeta\ngamma\n"
        new_text = "alpha\nBETA\ngamma\n"
        result = renderer.render(old_text, new_text)

        expect(result).to include('-beta')
        expect(result).to include('+BETA')
      end
    end

    context 'with multiple hunks (changes far apart)' do
      it 'produces separate @@ hunk headers' do
        # Build a file with changes far apart (more than 2 * context_lines + 1 lines apart)
        lines = (1..20).map { |i| "line #{i}" }
        old_text = lines.join("\n") + "\n"

        new_lines = lines.dup
        new_lines[1] = 'CHANGED 2'
        new_lines[18] = 'CHANGED 19'
        new_text = new_lines.join("\n") + "\n"

        result = renderer.render(old_text, new_text)
        hunk_headers = result.scan(/^@@.*@@$/)

        expect(hunk_headers.size).to eq(2)
      end
    end

    context 'with empty old_text (all additions)' do
      it 'shows all lines as additions' do
        old_text = ''
        new_text = "alpha\nbeta\ngamma\n"
        result = renderer.render(old_text, new_text)

        expect(result).to include('+alpha')
        expect(result).to include('+beta')
        expect(result).to include('+gamma')
      end

      it 'does not include any deleted lines' do
        old_text = ''
        new_text = "alpha\nbeta\n"
        result = renderer.render(old_text, new_text)

        diff_body = result.lines.reject { |l| l.start_with?('---', '+++', '@@') }
        expect(diff_body.any? { |l| l.start_with?('-') }).to be false
      end
    end

    context 'with empty new_text (all deletions)' do
      it 'shows all lines as deletions' do
        old_text = "alpha\nbeta\ngamma\n"
        new_text = ''
        result = renderer.render(old_text, new_text)

        expect(result).to include('-alpha')
        expect(result).to include('-beta')
        expect(result).to include('-gamma')
      end

      it 'does not include any added lines' do
        old_text = "alpha\nbeta\n"
        new_text = ''
        result = renderer.render(old_text, new_text)

        diff_body = result.lines.reject { |l| l.start_with?('---', '+++', '@@') }
        expect(diff_body.any? { |l| l.start_with?('+') }).to be false
      end
    end

    context 'with a custom filename' do
      it 'includes the filename in the header' do
        old_text = "old\n"
        new_text = "new\n"
        result = renderer.render(old_text, new_text, filename: 'app/models/user.rb')

        expect(result).to include('--- a/app/models/user.rb')
        expect(result).to include('+++ b/app/models/user.rb')
      end
    end

    context 'with the default filename' do
      it 'uses "file" in the header' do
        old_text = "old\n"
        new_text = "new\n"
        result = renderer.render(old_text, new_text)

        expect(result).to include('--- a/file')
        expect(result).to include('+++ b/file')
      end
    end

    it 'outputs the result to $stdout' do
      old_text = "old\n"
      new_text = "new\n"
      result = renderer.render(old_text, new_text)

      expect($stdout).to have_received(:puts).with(result)
    end
  end

  describe '#initialize' do
    context 'with enabled: false' do
      it 'creates a Pastel instance with colors disabled' do
        r = described_class.new(enabled: false)

        expect(r.pastel.enabled?).to be false
      end
    end

    context 'with enabled: true' do
      it 'creates a Pastel instance with colors enabled' do
        r = described_class.new(enabled: true)

        expect(r.pastel.enabled?).to be true
      end
    end

    context 'with custom context_lines' do
      it 'uses the custom context_lines for hunk grouping' do
        # With context_lines: 0, changes 2 lines apart should produce separate hunks
        r = described_class.new(enabled: false, context_lines: 0)

        lines = (1..10).map { |i| "line #{i}" }
        old_text = lines.join("\n") + "\n"

        new_lines = lines.dup
        new_lines[1] = 'CHANGED 2'
        new_lines[5] = 'CHANGED 6'
        new_text = new_lines.join("\n") + "\n"

        result = r.render(old_text, new_text)
        hunk_headers = result.scan(/^@@.*@@$/)

        expect(hunk_headers.size).to eq(2)
      end

      it 'merges nearby changes with larger context_lines' do
        # With context_lines: 10, those same changes should be in one hunk
        r = described_class.new(enabled: false, context_lines: 10)

        lines = (1..10).map { |i| "line #{i}" }
        old_text = lines.join("\n") + "\n"

        new_lines = lines.dup
        new_lines[1] = 'CHANGED 2'
        new_lines[5] = 'CHANGED 6'
        new_text = new_lines.join("\n") + "\n"

        result = r.render(old_text, new_text)
        hunk_headers = result.scan(/^@@.*@@$/)

        expect(hunk_headers.size).to eq(1)
      end
    end
  end
end
