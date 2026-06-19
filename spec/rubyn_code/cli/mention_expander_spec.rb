# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubynCode::CLI::MentionExpander do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      example.run
    end
  end

  subject(:expander) { described_class.new(project_root: @root) }

  def write(rel, content)
    path = File.join(@root, rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  describe '#expand' do
    it 'inlines the content of a mentioned file and reports the path' do
      write('lib/foo.rb', 'puts "hi"')

      text, paths = expander.expand('explain @lib/foo.rb please')

      expect(paths).to eq(['lib/foo.rb'])
      expect(text).to include('explain @lib/foo.rb please')
      expect(text).to include('@lib/foo.rb:')
      expect(text).to include('puts "hi"')
    end

    it 'leaves input untouched when there are no mentions' do
      expect(expander.expand('just a question')).to eq(['just a question', []])
    end

    it 'ignores mentions that do not resolve to a file' do
      text, paths = expander.expand('look at @does/not/exist.rb')
      expect(paths).to be_empty
      expect(text).to eq('look at @does/not/exist.rb')
    end

    it 'does not treat email addresses as mentions' do
      _text, paths = expander.expand('email me at matthew@tinycloud.com')
      expect(paths).to be_empty
    end

    it 'strips trailing punctuation before resolving' do
      write('a.rb', 'A')
      _text, paths = expander.expand('see (@a.rb).')
      expect(paths).to eq(['a.rb'])
    end

    it 'deduplicates repeated mentions of the same file' do
      write('a.rb', 'A')
      _text, paths = expander.expand('@a.rb and again @a.rb')
      expect(paths).to eq(['a.rb'])
    end

    it 'refuses to escape the project root' do
      _text, paths = expander.expand('peek at @../../etc/passwd')
      expect(paths).to be_empty
    end

    it 'does not inline directories' do
      FileUtils.mkdir_p(File.join(@root, 'lib'))
      _text, paths = expander.expand('open @lib')
      expect(paths).to be_empty
    end

    it 'truncates very large files' do
      write('big.txt', 'x' * (described_class::MAX_FILE_BYTES + 50))
      text, = expander.expand('@big.txt')
      expect(text).to include('… [truncated]')
    end
  end
end
