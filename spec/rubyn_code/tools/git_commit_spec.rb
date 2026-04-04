# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::GitCommit do
  let(:success_status) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failure_status) { instance_double(Process::Status, success?: false, exitstatus: 1) }

  def build_tool(dir)
    described_class.new(project_root: dir)
  end

  describe '#execute' do
    context 'when not a git repository' do
      it 'raises an error' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', '--is-inside-work-tree', chdir: dir)
            .and_return(['', 'not a git repo', failure_status])

          expect { tool.execute(message: 'test commit') }
            .to raise_error(RubynCode::Error, "Not a git repository: #{dir}")
        end
      end
    end

    context 'with empty commit message' do
      it 'raises an error for nil message' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)

          expect { tool.execute(message: nil) }
            .to raise_error(RubynCode::Error, 'Commit message cannot be empty')
        end
      end

      it 'raises an error for whitespace-only message' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)

          expect { tool.execute(message: '   ') }
            .to raise_error(RubynCode::Error, 'Commit message cannot be empty')
        end
      end
    end

    context 'staging files with "all"' do
      it 'runs git add -A' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)
          stub_stage_all(dir)
          stub_successful_commit(dir)

          tool.execute(message: 'test commit', files: 'all')

          expect(Open3).to have_received(:capture3)
            .with('git', 'add', '-A', chdir: dir)
        end
      end

      it 'defaults to staging all files' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)
          stub_stage_all(dir)
          stub_successful_commit(dir)

          tool.execute(message: 'test commit')

          expect(Open3).to have_received(:capture3)
            .with('git', 'add', '-A', chdir: dir)
        end
      end
    end

    context 'staging specific files' do
      it 'runs git add with file list' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)

          allow(Open3).to receive(:capture3)
            .with('git', 'add', '--', 'file1.rb', 'file2.rb', chdir: dir)
            .and_return(['', '', success_status])
          stub_successful_commit(dir)

          tool.execute(message: 'commit specific', files: 'file1.rb file2.rb')

          expect(Open3).to have_received(:capture3)
            .with('git', 'add', '--', 'file1.rb', 'file2.rb', chdir: dir)
        end
      end

      it 'raises error for empty file list after splitting' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)

          expect { tool.execute(message: 'test', files: '   ') }
            .to raise_error(RubynCode::Error, 'No files specified to stage')
        end
      end
    end

    context 'when staging fails' do
      it 'raises error with stderr message' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)

          allow(Open3).to receive(:capture3)
            .with('git', 'add', '-A', chdir: dir)
            .and_return(['', 'fatal: pathspec error', failure_status])

          expect { tool.execute(message: 'test') }
            .to raise_error(RubynCode::Error, 'Failed to stage files: fatal: pathspec error')
        end
      end
    end

    context 'successful commit' do
      it 'returns formatted commit output with branch and hash' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)
          stub_stage_all(dir)

          allow(Open3).to receive(:capture3)
            .with('git', 'commit', '-m', 'Add feature', chdir: dir)
            .and_return(["[main abc1234] Add feature\n 1 file changed", '', success_status])

          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', '--short', 'HEAD', chdir: dir)
            .and_return(["abc1234\n", '', success_status])

          allow(Open3).to receive(:capture3)
            .with('git', 'branch', '--show-current', chdir: dir)
            .and_return(["main\n", '', success_status])

          result = tool.execute(message: 'Add feature')

          expect(result).to include('Committed on branch: main')
          expect(result).to include('Commit: abc1234')
          expect(result).to include('[main abc1234] Add feature')
        end
      end

      it 'handles detached HEAD' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)
          stub_stage_all(dir)

          allow(Open3).to receive(:capture3)
            .with('git', 'commit', '-m', 'detached commit', chdir: dir)
            .and_return(['committed', '', success_status])

          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', '--short', 'HEAD', chdir: dir)
            .and_return(["def5678\n", '', success_status])

          allow(Open3).to receive(:capture3)
            .with('git', 'branch', '--show-current', chdir: dir)
            .and_return(['', '', success_status])

          result = tool.execute(message: 'detached commit')

          expect(result).to include('Committed on branch: HEAD (detached)')
        end
      end

      it 'handles missing commit hash gracefully' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)
          stub_stage_all(dir)

          allow(Open3).to receive(:capture3)
            .with('git', 'commit', '-m', 'no hash', chdir: dir)
            .and_return(['committed', '', success_status])

          allow(Open3).to receive(:capture3)
            .with('git', 'rev-parse', '--short', 'HEAD', chdir: dir)
            .and_return(['', '', failure_status])

          allow(Open3).to receive(:capture3)
            .with('git', 'branch', '--show-current', chdir: dir)
            .and_return(["main\n", '', success_status])

          result = tool.execute(message: 'no hash')

          expect(result).to include('Committed on branch: main')
          expect(result).not_to include('Commit:')
        end
      end
    end

    context 'when nothing to commit' do
      it 'returns clean working tree message' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)
          stub_stage_all(dir)

          allow(Open3).to receive(:capture3)
            .with('git', 'commit', '-m', 'empty', chdir: dir)
            .and_return(['', 'nothing to commit, working tree clean', failure_status])

          result = tool.execute(message: 'empty')

          expect(result).to eq('Nothing to commit — working tree is clean.')
        end
      end
    end

    context 'when commit fails for other reasons' do
      it 'raises error with stderr' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_valid_git_repo(dir)
          stub_stage_all(dir)

          allow(Open3).to receive(:capture3)
            .with('git', 'commit', '-m', 'fail', chdir: dir)
            .and_return(['', 'permission denied', failure_status])

          expect { tool.execute(message: 'fail') }
            .to raise_error(RubynCode::Error, 'Commit failed: permission denied')
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

  private

  def stub_valid_git_repo(dir)
    allow(Open3).to receive(:capture3)
      .with('git', 'rev-parse', '--is-inside-work-tree', chdir: dir)
      .and_return(['true', '', success_status])
  end

  def stub_stage_all(dir)
    allow(Open3).to receive(:capture3)
      .with('git', 'add', '-A', chdir: dir)
      .and_return(['', '', success_status])
  end

  def stub_successful_commit(dir)
    allow(Open3).to receive(:capture3)
      .with('git', 'commit', '-m', anything, chdir: dir)
      .and_return(['committed', '', success_status])

    allow(Open3).to receive(:capture3)
      .with('git', 'rev-parse', '--short', 'HEAD', chdir: dir)
      .and_return(["abc1234\n", '', success_status])

    allow(Open3).to receive(:capture3)
      .with('git', 'branch', '--show-current', chdir: dir)
      .and_return(["main\n", '', success_status])
  end
end
