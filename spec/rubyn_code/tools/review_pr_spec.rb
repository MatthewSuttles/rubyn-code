# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::ReviewPr do
  describe '#execute' do
    def build_tool(dir)
      described_class.new(project_root: dir)
    end

    context 'when not a git repository' do
      it 'returns an error message' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          allow(tool).to receive(:system).and_return(false)

          result = tool.execute
          expect(result).to eq('Error: Not a git repository or git is not installed.')
        end
      end
    end

    context 'when current branch cannot be determined' do
      it 'returns an error message' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          allow(tool).to receive(:system).and_return(true)
          allow(tool).to receive(:`).and_return('')

          result = tool.execute
          expect(result).to eq('Error: Could not determine current branch.')
        end
      end
    end

    context 'when on the base branch' do
      it 'returns a message to switch branches' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          allow(tool).to receive(:system).and_return(true)
          allow(tool).to receive(:`).and_return("main\n")

          result = tool.execute(base_branch: 'main')
          expect(result).to include("You're on main")
          expect(result).to include("specify a different base")
        end
      end
    end

    context 'when base branch does not exist' do
      it 'tries origin/base_branch then returns error' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          allow(tool).to receive(:system).and_return(true)

          call_count = 0
          allow(tool).to receive(:`) do |cmd|
            call_count += 1
            case call_count
            when 1 # rev-parse --abbrev-ref HEAD
              "feature-branch\n"
            when 2 # rev-parse --verify main
              "\n"
            when 3 # rev-parse --verify origin/main
              "\n"
            else
              ''
            end
          end

          result = tool.execute(base_branch: 'main')
          expect(result).to eq("Error: Base branch 'origin/main' not found.")
        end
      end
    end

    context 'when base branch exists as origin/base_branch' do
      it 'falls back to origin/ prefix and proceeds' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          allow(tool).to receive(:system).and_return(true)

          call_count = 0
          allow(tool).to receive(:`) do |_cmd|
            call_count += 1
            case call_count
            when 1 then "feature-branch\n"           # current branch
            when 2 then "\n"                         # verify main (empty = not found)
            when 3 then "abc1234\n"                  # verify origin/main (found)
            when 4 then "diff content here\n"        # diff
            when 5 then " 1 file changed\n"          # stat
            when 6 then "app/models/user.rb\n"       # name-only
            when 7 then "abc1234 Some commit\n"      # log
            else ''
            end
          end

          result = tool.execute(base_branch: 'main')
          expect(result).to include('PR Review: feature-branch')
          expect(result).to include('diff content here')
        end
      end
    end

    context 'when diff is empty' do
      it 'returns no changes message' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          allow(tool).to receive(:system).and_return(true)

          call_count = 0
          allow(tool).to receive(:`) do |_cmd|
            call_count += 1
            case call_count
            when 1 then "feature\n"   # current branch
            when 2 then "abc123\n"    # verify base
            when 3 then "\n"          # empty diff
            else ''
            end
          end

          result = tool.execute
          expect(result).to eq('No changes found between feature and main.')
        end
      end
    end

    context 'with a normal diff' do
      let(:diff_output) { "+class User\n+end\n" }
      let(:stat_output) { " app/models/user.rb | 2 ++\n 1 file changed" }
      let(:files_output) { "app/models/user.rb\nspec/models/user_spec.rb\napp/views/users/index.html.erb\ndb/migrate/001_create_users.rb\nconfig/database.yml" }
      let(:log_output) { "abc1234 Add user model\ndef5678 Add user spec" }

      def stub_git_calls(tool)
        allow(tool).to receive(:system).and_return(true)

        call_count = 0
        allow(tool).to receive(:`) do |_cmd|
          call_count += 1
          case call_count
          when 1 then "feature\n"
          when 2 then "abc123\n"
          when 3 then diff_output
          when 4 then stat_output
          when 5 then files_output
          when 6 then log_output
          else ''
          end
        end
      end

      it 'includes PR review header with branch names' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_git_calls(tool)

          result = tool.execute
          expect(result).to include('# PR Review: feature → main')
        end
      end

      it 'includes summary stats' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_git_calls(tool)

          result = tool.execute
          expect(result).to include('## Summary')
          expect(result).to include('1 file changed')
        end
      end

      it 'categorizes ruby files' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_git_calls(tool)

          result = tool.execute
          # All .rb files count as Ruby (user.rb, user_spec.rb, 001_create_users.rb)
          expect(result).to include('Ruby: 3 files')
        end
      end

      it 'categorizes template files' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_git_calls(tool)

          result = tool.execute
          expect(result).to include('Templates: 1 files')
        end
      end

      it 'categorizes spec files' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_git_calls(tool)

          result = tool.execute
          expect(result).to include('Specs: 1 files')
        end
      end

      it 'categorizes migration files' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_git_calls(tool)

          result = tool.execute
          expect(result).to include('Migrations: 1 files')
        end
      end

      it 'categorizes config files' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_git_calls(tool)

          result = tool.execute
          expect(result).to include('Config: 1 files')
        end
      end

      it 'includes commit log' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_git_calls(tool)

          result = tool.execute
          expect(result).to include('## Commits')
          expect(result).to include('Add user model')
        end
      end

      it 'includes the full diff' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_git_calls(tool)

          result = tool.execute
          expect(result).to include('## Full Diff')
          expect(result).to include('+class User')
        end
      end

      it 'includes review instructions' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_git_calls(tool)

          result = tool.execute
          expect(result).to include('## Review Focus: ALL')
          expect(result).to include('Review all aspects')
        end
      end
    end

    context 'with focus areas' do
      def stub_normal_diff(tool)
        allow(tool).to receive(:system).and_return(true)
        call_count = 0
        allow(tool).to receive(:`) do |_cmd|
          call_count += 1
          case call_count
          when 1 then "feature\n"
          when 2 then "abc123\n"
          when 3 then "+code\n"
          when 4 then "1 file\n"
          when 5 then "file.rb\n"
          when 6 then "abc commit\n"
          else ''
          end
        end
      end

      it 'handles security focus' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_normal_diff(tool)

          result = tool.execute(focus: 'security')
          expect(result).to include('## Review Focus: SECURITY')
          expect(result).to include('SQL injection')
        end
      end

      it 'handles performance focus' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_normal_diff(tool)

          result = tool.execute(focus: 'performance')
          expect(result).to include('## Review Focus: PERFORMANCE')
          expect(result).to include('N+1 queries')
        end
      end

      it 'handles style focus' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_normal_diff(tool)

          result = tool.execute(focus: 'style')
          expect(result).to include('## Review Focus: STYLE')
          expect(result).to include('Ruby idioms')
        end
      end

      it 'handles testing focus' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_normal_diff(tool)

          result = tool.execute(focus: 'testing')
          expect(result).to include('## Review Focus: TESTING')
          expect(result).to include('Missing test coverage')
        end
      end

      it 'defaults to all focus for unknown values' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          stub_normal_diff(tool)

          result = tool.execute(focus: 'something_else')
          expect(result).to include('Review all aspects')
        end
      end
    end

    context 'when diff is very large' do
      it 'truncates the diff at 40000 chars' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          allow(tool).to receive(:system).and_return(true)

          large_diff = 'x' * 50_000
          call_count = 0
          allow(tool).to receive(:`) do |_cmd|
            call_count += 1
            case call_count
            when 1 then "feature\n"
            when 2 then "abc123\n"
            when 3 then large_diff
            when 4 then "stats\n"
            when 5 then "file.rb\n"
            when 6 then "commit\n"
            else ''
            end
          end

          result = tool.execute
          expect(result).to include('Diff (truncated')
          expect(result).to include('truncated 10000 chars')
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
