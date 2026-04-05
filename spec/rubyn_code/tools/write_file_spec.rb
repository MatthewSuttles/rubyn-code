# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::WriteFile do
  describe '#execute' do
    it 'writes content to a file' do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        tool.execute(path: 'output.txt', content: 'hello world')
        expect(File.read(File.join(dir, 'output.txt'))).to eq('hello world')
      end
    end

    it 'creates parent directories' do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        tool.execute(path: 'deep/nested/dir/file.txt', content: 'nested')
        expect(File.exist?(File.join(dir, 'deep/nested/dir/file.txt'))).to be true
      end
    end

    it 'returns byte count in the result' do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        result = tool.execute(path: 'f.txt', content: '12345')
        expect(result).to include('5 bytes')
      end
    end

    it 'blocks path traversal' do
      with_temp_project do |dir|
        tool = described_class.new(project_root: dir)
        expect { tool.execute(path: '../../../tmp/evil.txt', content: 'bad') }
          .to raise_error(RubynCode::PermissionDeniedError)
      end
    end

    context 'output format' do
      it 'shows "Created" with a preview for new files' do
        with_temp_project do |dir|
          tool = described_class.new(project_root: dir)
          result = tool.execute(path: 'new.rb', content: "class Foo\n  def bar\n    42\n  end\nend\n")
          expect(result).to include('Created new.rb')
          expect(result).to include('class Foo')
          expect(result).to include('def bar')
          expect(result).to match(/\d+│/)  # line numbers
        end
      end

      it 'shows "Updated" with a diff for existing files' do
        with_temp_project do |dir|
          File.write(File.join(dir, 'existing.rb'), "def old\n  1\nend\n")
          tool = described_class.new(project_root: dir)
          result = tool.execute(path: 'existing.rb', content: "def new_method\n  2\nend\n")
          expect(result).to include('Updated existing.rb')
          expect(result).to include('- def old')
          expect(result).to include('+ def new_method')
        end
      end

      it 'truncates long file previews' do
        with_temp_project do |dir|
          content = (1..30).map { |num| "line #{num}" }.join("\n")
          tool = described_class.new(project_root: dir)
          result = tool.execute(path: 'long.txt', content: content)
          expect(result).to include('more lines')
        end
      end
    end
  end
end
