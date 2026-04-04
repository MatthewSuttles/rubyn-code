# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::GitStatus do
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
      it 'shows clean status' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'init.rb'), '# init')
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute

          expect(result).to include('nothing to commit')
        end
      end

      it 'includes the branch name' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'init.rb'), '# init')
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute

          expect(result).to include('Branch:')
        end
      end
    end

    context 'with modified files' do
      it 'shows modified file in status' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'tracked.rb'), '# original')
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'tracked.rb'), '# modified')

          tool = build_tool(dir)
          result = tool.execute

          expect(result).to include('tracked.rb')
        end
      end
    end

    context 'with untracked files' do
      it 'shows untracked file in status' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'init.rb'), '# init')
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'untracked.rb'), '# new file')

          tool = build_tool(dir)
          result = tool.execute

          expect(result).to include('untracked.rb')
        end
      end
    end
  end

  describe '.tool_name' do
    it 'returns git_status' do
      expect(described_class.tool_name).to eq('git_status')
    end
  end
end
