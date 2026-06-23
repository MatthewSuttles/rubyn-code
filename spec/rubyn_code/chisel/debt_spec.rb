# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::Chisel::Debt do
  describe '.scan' do
    around do |example|
      Dir.mktmpdir('chisel_debt_') do |dir|
        @root = dir
        example.run
      end
    end

    def write(relpath, contents)
      full = File.join(@root, relpath)
      FileUtils.mkdir_p(File.dirname(full))
      File.write(full, contents)
    end

    it 'finds a marker with file, line, and note' do
      write('lib/a.rb', "class A\n  # chisel: inline this once there is a second caller\nend\n")

      items = described_class.scan(@root)

      expect(items.size).to eq(1)
      expect(items.first.file).to eq('lib/a.rb')
      expect(items.first.line).to eq(2)
      expect(items.first.note).to eq('inline this once there is a second caller')
    end

    it 'matches // comment leaders too' do
      write('app.rb', "x = 1 // chisel: drop this option\n")
      expect(described_class.scan(@root).first.note).to eq('drop this option')
    end

    it 'ignores comments that are not chisel markers' do
      write('lib/b.rb', "# TODO: something\n# just mentions chisel without a colon\n")
      expect(described_class.scan(@root)).to be_empty
    end

    it 'is case-sensitive so descriptive "Chisel:" comments are not markers' do
      write('lib/d.rb', "# Chisel: this is a section heading, not a deferral marker\n")
      expect(described_class.scan(@root)).to be_empty
    end

    it 'skips non-source directories' do
      write('vendor/bundle/x.rb', "# chisel: should be ignored\n")
      write('node_modules/y.rb', "# chisel: should be ignored\n")
      expect(described_class.scan(@root)).to be_empty
    end

    it 'only scans source extensions' do
      write('notes.txt', "# chisel: not a source file\n")
      expect(described_class.scan(@root)).to be_empty
    end

    it 'returns results sorted by file' do
      write('lib/z.rb', "# chisel: last\n")
      write('lib/a.rb', "# chisel: first\n")
      expect(described_class.scan(@root).map(&:file)).to eq(['lib/a.rb', 'lib/z.rb'])
    end

    it 'returns [] for a nil or missing root' do
      expect(described_class.scan(nil)).to eq([])
      expect(described_class.scan('/no/such/dir/xyz')).to eq([])
    end

    it 'does not raise on an unreadable file' do
      write('lib/c.rb', "# chisel: present\n")
      allow(File).to receive(:foreach).and_raise(Errno::EACCES)
      expect { described_class.scan(@root) }.not_to raise_error
      expect(described_class.scan(@root)).to eq([])
    end
  end
end
