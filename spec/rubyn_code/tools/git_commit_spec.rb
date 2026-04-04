# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::GitCommit do
  def build_tool(dir)
    described_class.new(project_root: dir)
  end

  # Creates a real git repo in a temp directory for integration-level tests.
  # This ensures we test actual git interactions, not stubs.
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

          expect { tool.execute(message: 'test commit') }
            .to raise_error(RubynCode::Error, "Not a git repository: #{dir}")
        end
      end
    end

    context 'with empty commit message' do
      it 'raises an error for nil message' do
        with_git_repo do |dir|
          tool = build_tool(dir)

          expect { tool.execute(message: nil) }
            .to raise_error(RubynCode::Error, 'Commit message cannot be empty')
        end
      end

      it 'raises an error for whitespace-only message' do
        with_git_repo do |dir|
          tool = build_tool(dir)

          expect { tool.execute(message: '   ') }
            .to raise_error(RubynCode::Error, 'Commit message cannot be empty')
        end
      end
    end

    context 'staging files with "all"' do
      it 'stages and commits all files' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'foo.rb'), '# frozen_string_literal: true')
          tool = build_tool(dir)

          result = tool.execute(message: 'initial commit', files: 'all')

          expect(result).to include('Committed on branch:')
          expect(result).to include('Commit:')
        end
      end

      it 'defaults to staging all files' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'bar.rb'), '# frozen_string_literal: true')
          tool = build_tool(dir)

          result = tool.execute(message: 'default staging commit')

          expect(result).to include('Committed on branch:')
        end
      end
    end

    context 'staging specific files' do
      it 'commits only the specified files' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'staged.rb'), '# staged')
          File.write(File.join(dir, 'unstaged.rb'), '# unstaged')
          tool = build_tool(dir)

          result = tool.execute(message: 'selective commit', files: 'staged.rb')

          expect(result).to include('Committed on branch:')

          # Verify only staged.rb was committed
          log_output = `cd #{dir} && git show --name-only --format="" HEAD`.strip
          expect(log_output).to eq('staged.rb')
        end
      end

      it 'raises error for empty file list after splitting' do
        with_git_repo do |dir|
          tool = build_tool(dir)

          expect { tool.execute(message: 'test', files: '   ') }
            .to raise_error(RubynCode::Error, 'No files specified to stage')
        end
      end
    end

    context 'successful commit' do
      it 'returns formatted commit output with branch and hash' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'test.rb'), '# test')
          tool = build_tool(dir)

          result = tool.execute(message: 'my test commit')

          expect(result).to include('Committed on branch:')
          expect(result).to include('Commit:')
          expect(result).to match(/[0-9a-f]{7}/) # short SHA
        end
      end

      it 'includes the commit message in the output' do
        with_git_repo do |dir|
          File.write(File.join(dir, 'hello.rb'), '# hello')
          tool = build_tool(dir)

          result = tool.execute(message: 'a meaningful commit')

          expect(result).to include('a meaningful commit')
        end
      end
    end

    context 'when nothing to commit' do
      it 'returns clean working tree message' do
        with_git_repo do |dir|
          # Make an initial commit so the repo isn't empty
          File.write(File.join(dir, 'init.rb'), '# init')
          system('git add -A && git commit -m "init"', chdir: dir, out: File::NULL, err: File::NULL)

          tool = build_tool(dir)
          result = tool.execute(message: 'nothing here')

          expect(result).to eq('Nothing to commit — working tree is clean.')
        end
      end
    end
  end

  describe '.tool_name' do
    it 'returns git_commit' do
      expect(described_class.tool_name).to eq('git_commit')
    end
  end

  describe '.requires_confirmation?' do
    it 'is true' do
      expect(described_class.requires_confirmation?).to be true
    end
  end

  describe '.risk_level' do
    it 'is write' do
      expect(described_class.risk_level).to eq(:write)
    end
  end
end
