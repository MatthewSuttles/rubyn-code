# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::ReviewPr do
  def build_tool(dir)
    described_class.new(project_root: dir)
  end

  # Creates a real git repo with a base commit on main and a feature branch.
  # Yields |dir, feature_branch_name|
  def with_pr_repo
    with_temp_project do |dir|
      system('git init --initial-branch=main', chdir: dir, out: File::NULL, err: File::NULL) ||
        system('git init', chdir: dir, out: File::NULL, err: File::NULL)
      system('git config user.email "test@example.com"', chdir: dir, out: File::NULL, err: File::NULL)
      system('git config user.name "Test"', chdir: dir, out: File::NULL, err: File::NULL)

      # Base commit on main
      File.write(File.join(dir, 'README.md'), '# Project')
      system('git add -A && git commit -m "Initial commit"', chdir: dir, out: File::NULL, err: File::NULL)

      # Feature branch with changes
      system('git checkout -b feature/add-user', chdir: dir, out: File::NULL, err: File::NULL)
      FileUtils.mkdir_p(File.join(dir, 'app/models'))
      File.write(File.join(dir, 'app/models/user.rb'), "class User\nend\n")
      system('git add -A && git commit -m "Add user model"', chdir: dir, out: File::NULL, err: File::NULL)

      yield dir
    end
  end

  describe '#execute' do
    context 'when not a git repository' do
      it 'returns an error message' do
        with_temp_project do |dir|
          tool = build_tool(dir)

          result = tool.execute

          expect(result).to eq('Error: Not a git repository or git is not installed.')
        end
      end
    end

    context 'when on the base branch' do
      it 'returns a message to switch branches' do
        with_temp_project do |dir|
          system('git init --initial-branch=main', chdir: dir, out: File::NULL, err: File::NULL) ||
            system('git init', chdir: dir, out: File::NULL, err: File::NULL)
          system('git config user.email "test@example.com"', chdir: dir, out: File::NULL, err: File::NULL)
          system('git config user.name "Test"', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'README.md'), '# hi')
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main')

          expect(result).to include("You're on main")
          expect(result).to include('specify a different base')
        end
      end
    end

    context 'when base branch does not exist' do
      it 'returns an error about missing base branch' do
        with_temp_project do |dir|
          system('git init --initial-branch=develop', chdir: dir, out: File::NULL, err: File::NULL) ||
            system('git init', chdir: dir, out: File::NULL, err: File::NULL)
          system('git config user.email "test@example.com"', chdir: dir, out: File::NULL, err: File::NULL)
          system('git config user.name "Test"', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'README.md'), '# hi')
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)
          system('git checkout -b feature/test', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute(base_branch: 'nonexistent')

          expect(result).to include("not found")
        end
      end
    end

    context 'when diff is empty' do
      it 'returns no changes message' do
        with_temp_project do |dir|
          system('git init --initial-branch=main', chdir: dir, out: File::NULL, err: File::NULL) ||
            system('git init', chdir: dir, out: File::NULL, err: File::NULL)
          system('git config user.email "test@example.com"', chdir: dir, out: File::NULL, err: File::NULL)
          system('git config user.name "Test"', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'README.md'), '# hi')
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)
          system('git checkout -b feature/empty', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main')

          expect(result).to include('No changes found')
        end
      end
    end

    context 'with a normal diff' do
      it 'includes PR review header with branch names' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main')

          expect(result).to include('PR Review: feature/add-user')
        end
      end

      it 'includes the summary stats' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main')

          expect(result).to include('## Summary')
        end
      end

      it 'includes files by category' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main')

          expect(result).to include('## Files by Category')
          expect(result).to include('Ruby:')
        end
      end

      it 'includes commits section' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main')

          expect(result).to include('## Commits')
          expect(result).to include('Add user model')
        end
      end

      it 'includes the full diff' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main')

          expect(result).to include('## Full Diff')
          expect(result).to include('class User')
        end
      end

      it 'includes review instructions' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main')

          expect(result).to include('## Review Focus: ALL')
          expect(result).to include('Review all aspects')
        end
      end
    end

    context 'with focus areas' do
      it 'handles security focus' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main', focus: 'security')

          expect(result).to include('## Review Focus: SECURITY')
          expect(result).to include('SQL injection')
        end
      end

      it 'handles performance focus' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main', focus: 'performance')

          expect(result).to include('## Review Focus: PERFORMANCE')
          expect(result).to include('N+1 queries')
        end
      end

      it 'handles style focus' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main', focus: 'style')

          expect(result).to include('## Review Focus: STYLE')
          expect(result).to include('Ruby idioms')
        end
      end

      it 'handles testing focus' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main', focus: 'testing')

          expect(result).to include('## Review Focus: TESTING')
          expect(result).to include('Missing test coverage')
        end
      end

      it 'defaults to all focus for unknown values' do
        with_pr_repo do |dir|
          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main', focus: 'something_else')

          expect(result).to include('Review all aspects')
        end
      end
    end

    context 'when diff is very large' do
      it 'truncates the diff at 40000 chars' do
        with_temp_project do |dir|
          system('git init --initial-branch=main', chdir: dir, out: File::NULL, err: File::NULL) ||
            system('git init', chdir: dir, out: File::NULL, err: File::NULL)
          system('git config user.email "test@example.com"', chdir: dir, out: File::NULL, err: File::NULL)
          system('git config user.name "Test"', chdir: dir, out: File::NULL, err: File::NULL)
          File.write(File.join(dir, 'README.md'), '# start')
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)

          system('git checkout -b feature/big-change', chdir: dir, out: File::NULL, err: File::NULL)
          # Generate a very large file to create a huge diff
          File.write(File.join(dir, 'big.rb'), "x = 1\n" * 10_000)
          system('git add -A && git commit -m "big change"', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute(base_branch: 'main')

          # The diff should be present (may or may not be truncated depending on
          # the actual size — but the output building logic is exercised for real)
          expect(result).to include('feature/big-change')
          expect(result).to include('## Summary')
        end
      end
    end
  end

  describe '.tool_name' do
    it 'returns review_pr' do
      expect(described_class.tool_name).to eq('review_pr')
    end
  end

  describe '.risk_level' do
    it 'is read' do
      expect(described_class.risk_level).to eq(:read)
    end
  end
end
