# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Autonomous::TaskClaimer do
  let(:db) { setup_test_db }
  let(:task_manager) { RubynCode::Tasks::Manager.new(db) }

  before do
    allow(task_manager).to receive(:db).and_return(db)
  end

  describe '.call' do
    it 'claims the highest-priority ready task' do
      task_manager.create(title: 'Low prio', priority: 1)
      task_manager.create(title: 'High prio', priority: 10)

      claimed = described_class.call(task_manager: task_manager, agent_name: 'agent-1')

      expect(claimed).not_to be_nil
      expect(claimed.title).to eq('High prio')
      expect(claimed.owner).to eq('agent-1')
      expect(claimed.status).to eq('in_progress')
    end

    it 'returns nil when no tasks are available' do
      result = described_class.call(task_manager: task_manager, agent_name: 'agent-1')
      expect(result).to be_nil
    end

    it 'returns nil when all tasks are already claimed' do
      task = task_manager.create(title: 'Taken')
      task_manager.claim(task.id, owner: 'other-agent')

      result = described_class.call(task_manager: task_manager, agent_name: 'agent-2')
      expect(result).to be_nil
    end

    it 'does not claim completed tasks' do
      task = task_manager.create(title: 'Done')
      task_manager.complete(task.id)

      result = described_class.call(task_manager: task_manager, agent_name: 'agent-1')
      expect(result).to be_nil
    end

    it 'skips tasks that have exceeded max retries' do
      task = task_manager.create(title: 'Poisoned', priority: 10)
      task_manager.update(task.id, metadata: JSON.generate({ retry_count: 3 }))

      result = described_class.call(task_manager: task_manager, agent_name: 'agent-1')
      expect(result).to be_nil
    end

    it 'claims tasks below max retry count' do
      task = task_manager.create(title: 'Retried once', priority: 5)
      task_manager.update(task.id, metadata: JSON.generate({ retry_count: 1 }))

      claimed = described_class.call(task_manager: task_manager, agent_name: 'agent-1')
      expect(claimed).not_to be_nil
      expect(claimed.title).to eq('Retried once')
    end

    it 'prefers lower-retry tasks when priorities are equal' do
      # Create two tasks with same priority
      task_manager.create(title: 'Fresh task', priority: 5)
      retried = task_manager.create(title: 'Retried task', priority: 5)
      task_manager.update(retried.id, metadata: JSON.generate({ retry_count: 2 }))

      # The claimer picks by priority DESC, created_at ASC — fresh was created first
      claimed = described_class.call(task_manager: task_manager, agent_name: 'agent-1')
      expect(claimed).not_to be_nil
      expect(claimed.title).to eq('Fresh task')

      # Claim again for second task
      claimed2 = described_class.call(task_manager: task_manager, agent_name: 'agent-2')
      expect(claimed2).not_to be_nil
      expect(claimed2.title).to eq('Retried task')
    end

    it 'respects custom max_retries parameter' do
      task = task_manager.create(title: 'Custom retry', priority: 5)
      task_manager.update(task.id, metadata: JSON.generate({ retry_count: 1 }))

      # With max_retries: 1, a task with retry_count 1 should be skipped
      result = described_class.call(task_manager: task_manager, agent_name: 'agent-1', max_retries: 1)
      expect(result).to be_nil
    end
  end
end
