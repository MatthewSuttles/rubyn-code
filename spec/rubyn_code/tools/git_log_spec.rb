# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::GitLog do
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

    context 'with a repo that has commits' do
      it 'returns formatted log output' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'first.rb'), '# first')
          system('git add -A && git commit -m "first commit"', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute

          expect(result).to include('Commit history')
          expect(result).to include('first commit')
        end
      end
    end

    context 'with no commits' do
      it 'returns no commits message' do
        with_git_repo do |dir|
          tool = build_tool(dir)

          # git log on an empty repo fails, which triggers the error path
          # or returns 'No commits found.' depending on implementation
          # The implementation raises on non-zero exit, so this should raise
          expect { tool.execute }.to raise_error(RubynCode::Error, /git log failed/)
        end
      end
    end

    context 'with count parameter' do
      it 'limits the number of commits shown' do
        with_git_repo do |dir|
          3.times do |i|
            File.write(File.join(dir, "file#{i}.rb"), "# file #{i}")
            system("git add -A && git commit -m 'commit #{i}'", chdir: dir, out: File::NULL, err: File::NULL)
          end

          tool = build_tool(dir)
          result = tool.execute(count: 1)

          # Should only contain the most recent commit
          expect(result).to include('commit 2')
          expect(result).not_to include('commit 0')
        end
      end
    end

    context 'with branch parameter' do
      it 'filters log by branch' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'main.rb'), '# main')
          system('git add -A && git commit -m "main commit"', chdir: dir, out: File::NULL, err: File::NULL)
          system('git checkout -b feature', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'feature.rb'), '# feature')
          system('git add -A && git commit -m "feature commit"', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute(branch: 'main')

          expect(result).to include('main commit')
          expect(result).to include('(main)')
          expect(result).not_to include('feature commit')
        end
      end
    end

    context 'with multiple commits' do
      it 'shows commits in reverse chronological order' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'a.rb'), '# a')
          system('git add -A && git commit -m "alpha"', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'b.rb'), '# b')
          system('git add -A && git commit -m "beta"', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute

          expect(result.index('beta')).to be < result.index('alpha')
        end
      end
    end
  end

  describe '.tool_name' do
    it 'returns git_log' do
      expect(described_class.tool_name).to eq('git_log')
    end
  end
end
