# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::GitDiff do
  def build_tool(dir)
    described_class.new(project_root: dir)
  end

  def with_git_repo
    with_temp_project do |dir|
      system('git init --initial-branch=main', chdir: dir, out: File::NULL, err: File::NULL) ||
        system('git init', chdir: dir, out: File::NULL, err: File::NULL)
      system('git config user.email "test@example.com"', chdir: dir, out: File::NULL, err: File::NULL)
      system('git config user.name "Test"', chdir: dir, out: File::NULL, err: File::NULL)
      yield dir
    end
  end

  describe '#execute' do
    context 'when not a git repository' do
      it 'raises an error' do
        with_temp_project do |dir|
          tool = build_tool(dir)

          expect { tool.execute }
            .to raise_error(RubynCode::Error, /Not a git repository/)
        end
      end
    end

    context 'with a clean working tree' do
      it 'shows no differences' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'init.rb'), '# init')
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute

          expect(result).to include('No differences found')
        end
      end
    end

    context 'with modified files' do
      it 'shows diff for unstaged changes' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'hello.rb'), "# original\n")
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'hello.rb'), "# modified\n")

          tool = build_tool(dir)
          result = tool.execute

          expect(result).to include('git diff (unstaged)')
          expect(result).to include('hello.rb')
          expect(result).to include('# modified')
        end
      end
    end

    context 'with target: "staged"' do
      it 'shows diff for staged changes' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'staged.rb'), "# original\n")
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'staged.rb'), "# staged change\n")
          system('git add staged.rb', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute(target: 'staged')

          expect(result).to include('git diff (staged)')
          expect(result).to include('staged.rb')
          expect(result).to include('# staged change')
        end
      end
    end

    context 'with target: "cached"' do
      it 'treats cached the same as staged' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'cached.rb'), "# original\n")
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'cached.rb'), "# cached change\n")
          system('git add cached.rb', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute(target: 'cached')

          expect(result).to include('cached.rb')
          expect(result).to include('# cached change')
        end
      end
    end

    context 'with a branch ref as target' do
      it 'shows diff against the specified ref' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'base.rb'), "# base\n")
          system('git add -A && git commit -m "base"', chdir: dir, out: File::NULL, err: File::NULL)
          system('git checkout -b feature', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'base.rb'), "# feature change\n")
          system('git add -A && git commit -m "feature"', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute(target: 'main')

          expect(result).to include('base.rb')
          expect(result).to include('# feature change')
        end
      end
    end
  end

  describe '.tool_name' do
    it 'returns git_diff' do
      expect(described_class.tool_name).to eq('git_diff')
    end
  end
end
