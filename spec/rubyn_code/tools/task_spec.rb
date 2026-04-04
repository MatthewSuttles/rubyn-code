# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::Task do
  let(:db) { setup_test_db }

  before do
    allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)
  end

  def build_tool(dir)
    described_class.new(project_root: dir)
  end

  describe '#execute' do
    context 'action: create' do
      it 'creates a task with title and returns formatted output' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          result = tool.execute(action: 'create', title: 'Implement feature X')

          expect(result).to include('Created task: Implement feature X')
          expect(result).to include('ID:')
          expect(result).to include('Status:   pending')
          expect(result).to include('Priority: 0')
        end
      end

      it 'creates a task with description' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          result = tool.execute(action: 'create', title: 'Task A', description: 'Details here')

          expect(result).to include('Description: Details here')
        end
      end

      it 'creates a task with session_id' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          result = tool.execute(action: 'create', title: 'Task B', session_id: 'sess_123')

          expect(result).to include('Session:  sess_123')
        end
      end

      it 'creates a task with priority' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          result = tool.execute(action: 'create', title: 'High prio', priority: 10)

          expect(result).to include('Priority: 10')
        end
      end

      it 'raises error when title is nil' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'create') }
            .to raise_error(RubynCode::Error, 'title is required for create')
        end
      end

      it 'raises error when title is empty string' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'create', title: '') }
            .to raise_error(RubynCode::Error, 'title is required for create')
        end
      end

      it 'creates a task with blocked_by dependencies' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          result_a = tool.execute(action: 'create', title: 'Dep task')
          # Extract the ID from the result
          id_line = result_a.lines.find { |l| l.include?('ID:') }
          dep_id = id_line.strip.split('ID:').last.strip

          result_b = tool.execute(action: 'create', title: 'Blocked task', blocked_by: [dep_id])
          expect(result_b).to include('Status:   blocked')
        end
      end
    end

    context 'action: update' do
      it 'updates a task status' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          create_result = tool.execute(action: 'create', title: 'To update')
          task_id = extract_id(create_result)

          result = tool.execute(action: 'update', task_id: task_id, status: 'in_progress')
          expect(result).to include('Updated task: To update')
          expect(result).to include('Status:   in_progress')
        end
      end

      it 'updates priority' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          create_result = tool.execute(action: 'create', title: 'Prio update')
          task_id = extract_id(create_result)

          result = tool.execute(action: 'update', task_id: task_id, priority: 5)
          expect(result).to include('Priority: 5')
        end
      end

      it 'updates owner' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          create_result = tool.execute(action: 'create', title: 'Owner update')
          task_id = extract_id(create_result)

          result = tool.execute(action: 'update', task_id: task_id, owner: 'alice')
          expect(result).to include('Owner:    alice')
        end
      end

      it 'raises error when task_id is nil' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'update', status: 'done') }
            .to raise_error(RubynCode::Error, 'task_id is required for update')
        end
      end

      it 'raises error when task_id is empty' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'update', task_id: '') }
            .to raise_error(RubynCode::Error, 'task_id is required for update')
        end
      end

      it 'raises error when task not found' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'update', task_id: 'nonexistent', status: 'done') }
            .to raise_error(RubynCode::Error, 'Task not found: nonexistent')
        end
      end
    end

    context 'action: complete' do
      it 'completes a task' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          create_result = tool.execute(action: 'create', title: 'To complete')
          task_id = extract_id(create_result)

          result = tool.execute(action: 'complete', task_id: task_id)
          expect(result).to include('Completed task: To complete')
          expect(result).to include('Status:   completed')
        end
      end

      it 'completes a task with result text' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          create_result = tool.execute(action: 'create', title: 'With result')
          task_id = extract_id(create_result)

          result = tool.execute(action: 'complete', task_id: task_id, result: 'All 5 tests pass')
          expect(result).to include('Result:   All 5 tests pass')
        end
      end

      it 'raises error when task_id is nil' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'complete') }
            .to raise_error(RubynCode::Error, 'task_id is required for complete')
        end
      end

      it 'raises error when task_id is empty' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'complete', task_id: '') }
            .to raise_error(RubynCode::Error, 'task_id is required for complete')
        end
      end

      it 'raises error when task not found' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'complete', task_id: 'ghost') }
            .to raise_error(RubynCode::Error, 'Task not found: ghost')
        end
      end
    end

    context 'action: list' do
      it 'returns no tasks message when empty' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          result = tool.execute(action: 'list')
          expect(result).to eq('No tasks found.')
        end
      end

      it 'lists all tasks' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          tool.execute(action: 'create', title: 'Task 1')
          tool.execute(action: 'create', title: 'Task 2')

          result = tool.execute(action: 'list')
          expect(result).to include('Found 2 task(s)')
          expect(result).to include('Task 1')
          expect(result).to include('Task 2')
        end
      end

      it 'filters by status' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          create_result = tool.execute(action: 'create', title: 'Active task')
          task_id = extract_id(create_result)
          tool.execute(action: 'update', task_id: task_id, status: 'in_progress')
          tool.execute(action: 'create', title: 'Pending task')

          result = tool.execute(action: 'list', status: 'in_progress')
          expect(result).to include('Found 1 task(s)')
          expect(result).to include('Active task')
          expect(result).not_to include('Pending task')
        end
      end

      it 'filters by session_id' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          tool.execute(action: 'create', title: 'Session A task', session_id: 'sess_a')
          tool.execute(action: 'create', title: 'Session B task', session_id: 'sess_b')

          result = tool.execute(action: 'list', session_id: 'sess_a')
          expect(result).to include('Found 1 task(s)')
          expect(result).to include('Session A task')
        end
      end

      it 'includes owner in task line when set' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          create_result = tool.execute(action: 'create', title: 'Owned task')
          task_id = extract_id(create_result)
          tool.execute(action: 'update', task_id: task_id, owner: 'bob')

          result = tool.execute(action: 'list')
          expect(result).to include('(bob)')
        end
      end
    end

    context 'action: get' do
      it 'retrieves a single task by ID' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          create_result = tool.execute(action: 'create', title: 'Fetch me')
          task_id = extract_id(create_result)

          result = tool.execute(action: 'get', task_id: task_id)
          expect(result).to include('Fetch me')
          expect(result).to include("ID:       #{task_id}")
        end
      end

      it 'raises error when task_id is nil' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'get') }
            .to raise_error(RubynCode::Error, 'task_id is required for get')
        end
      end

      it 'raises error when task_id is empty' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'get', task_id: '') }
            .to raise_error(RubynCode::Error, 'task_id is required for get')
        end
      end

      it 'raises error when task not found' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'get', task_id: 'missing') }
            .to raise_error(RubynCode::Error, 'Task not found: missing')
        end
      end
    end

    context 'unknown action' do
      it 'raises error with valid actions listed' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'destroy') }
            .to raise_error(RubynCode::Error, /Unknown task action: destroy/)
        end
      end

      it 'lists valid actions in error message' do
        with_temp_project do |dir|
          tool = build_tool(dir)
          expect { tool.execute(action: 'invalid') }
            .to raise_error(RubynCode::Error, /create, update, complete, list, get/)
        end
      end
    end
  end

  describe '.tool_name' do
    it 'returns task' do
      expect(described_class.tool_name).to eq('task')
    end
  end

  describe '.risk_level' do
    it 'is write' do
      expect(described_class.risk_level).to eq(:write)
    end
  end

  describe '.requires_confirmation?' do
    it 'is false' do
      expect(described_class.requires_confirmation?).to be false
    end
  end

  private

  def extract_id(result)
    id_line = result.lines.find { |l| l.include?('ID:') }
    id_line.strip.split('ID:').last.strip
  end
end
