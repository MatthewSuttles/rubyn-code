# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::EditFile do
  describe '#execute' do
    it 'replaces text in a file' do
      with_temp_project do |dir|
        create_test_file(dir, 'app.rb', "def hello\n  puts 'hi'\nend\n")
        tool = described_class.new(project_root: dir)
        tool.execute(path: 'app.rb', old_text: "puts 'hi'", new_text: "puts 'bye'")
        expect(File.read(File.join(dir, 'app.rb'))).to include("puts 'bye'")
      end
    end

    it 'fails if old_text is not found' do
      with_temp_project do |dir|
        create_test_file(dir, 'app.rb', 'unchanged content')
        tool = described_class.new(project_root: dir)
        expect { tool.execute(path: 'app.rb', old_text: 'nonexistent', new_text: 'x') }
          .to raise_error(RubynCode::Error, /not found/)
      end
    end

    it 'fails if old_text is not unique without replace_all' do
      with_temp_project do |dir|
        create_test_file(dir, 'dup.rb', "foo\nfoo\nbar\n")
        tool = described_class.new(project_root: dir)
        expect { tool.execute(path: 'dup.rb', old_text: 'foo', new_text: 'baz') }
          .to raise_error(RubynCode::Error, /found 2 times/)
      end
    end

    it 'replaces all occurrences with replace_all: true' do
      with_temp_project do |dir|
        create_test_file(dir, 'multi.rb', "aaa bbb aaa ccc aaa\n")
        tool = described_class.new(project_root: dir)
        result = tool.execute(path: 'multi.rb', old_text: 'aaa', new_text: 'zzz', replace_all: true)
        expect(result).to include('3 replacement')
        expect(File.read(File.join(dir, 'multi.rb'))).to eq("zzz bbb zzz ccc zzz\n")
      end
    end

    context 'output format' do
      it 'shows the file name and replacement count' do
        with_temp_project do |dir|
          create_test_file(dir, 'app.rb', "old_value = 1\n")
          tool = described_class.new(project_root: dir)
          result = tool.execute(path: 'app.rb', old_text: 'old_value', new_text: 'new_value')
          expect(result).to include('Edited app.rb')
          expect(result).to include('1 replacement')
        end
      end

      it 'shows a diff with - and + lines' do
        with_temp_project do |dir|
          create_test_file(dir, 'model.rb', "class User\n  def name\n    'old'\n  end\nend\n")
          tool = described_class.new(project_root: dir)
          result = tool.execute(path: 'model.rb', old_text: "    'old'", new_text: "    'new'")
          expect(result).to include("- ")
          expect(result).to include("+ ")
          expect(result).to include("'old'")
          expect(result).to include("'new'")
        end
      end

      it 'shows the line number where the edit occurred' do
        with_temp_project do |dir|
          create_test_file(dir, 'lines.rb', "line1\nline2\ntarget\nline4\n")
          tool = described_class.new(project_root: dir)
          result = tool.execute(path: 'lines.rb', old_text: 'target', new_text: 'replaced')
          expect(result).to include('@@ line 3 @@')
        end
      end
    end
  end
end
