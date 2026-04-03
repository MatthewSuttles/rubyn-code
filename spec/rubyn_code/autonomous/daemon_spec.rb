# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Autonomous::Daemon do
  let(:db) { setup_test_db }
  let(:task_manager) { RubynCode::Tasks::Manager.new(db) }
  let(:llm_client) { instance_double(RubynCode::LLM::Client) }
  let(:mailbox) { instance_double('Mailbox', pending_for: []) }
  let(:state_changes) { [] }

  let(:daemon) do
    described_class.new(
      agent_name: 'test-daemon',
      role: 'test agent',
      llm_client: llm_client,
      project_root: Dir.pwd,
      task_manager: task_manager,
      mailbox: mailbox,
      max_runs: 3,
      max_cost: 5.0,
      poll_interval: 0.01,
      idle_timeout: 0.05,
      on_state_change: ->(old_s, new_s) { state_changes << [old_s, new_s] }
    )
  end

  before do
    # Prevent real signal traps in tests
    allow(Signal).to receive(:trap)
  end

  describe '#initialize' do
    it 'starts in :spawned state' do
      expect(daemon.state).to eq(:spawned)
    end

    it 'initializes counters to zero' do
      expect(daemon.runs_completed).to eq(0)
      expect(daemon.total_cost).to eq(0.0)
    end
  end

  describe '#status' do
    it 'returns a snapshot hash' do
      status = daemon.status
      expect(status).to include(
        agent_name: 'test-daemon',
        role: 'test agent',
        state: :spawned,
        runs_completed: 0,
        max_runs: 3,
        max_cost: 5.0
      )
    end
  end

  describe '#running?' do
    it 'is false when spawned' do
      expect(daemon.running?).to be false
    end
  end

  describe '#stop!' do
    it 'sets the stop_requested flag' do
      daemon.stop!
      expect(daemon.status[:stop_requested]).to be true
    end
  end

  describe '#start!' do
    context 'with no tasks available' do
      it 'transitions through working -> idle -> shutting_down -> stopped' do
        daemon.start!

        expect(daemon.state).to eq(:stopped)
        expect(state_changes).to include(
          [:spawned, :working],
          [:working, :idle],
          %i[idle shutting_down],
          %i[shutting_down stopped]
        )
      end

      it 'shuts down after idle timeout' do
        daemon.start!
        expect(daemon.runs_completed).to eq(0)
      end
    end

    context 'with tasks available' do
      let(:text_response) do
        RubynCode::LLM::Response.new(
          id: 'msg_test',
          content: [RubynCode::LLM::TextBlock.new(text: 'Task completed successfully')],
          stop_reason: 'end_turn',
          usage: RubynCode::LLM::Usage.new(input_tokens: 100, output_tokens: 50)
        )
      end

      before do
        allow(llm_client).to receive(:chat).and_return(text_response)
      end

      it 'claims and completes tasks' do
        task_manager.create(title: 'Test task', description: 'Do a thing', priority: 5)

        daemon.start!

        expect(daemon.runs_completed).to eq(1)
        completed = task_manager.list(status: 'completed')
        expect(completed.length).to eq(1)
        expect(completed.first.title).to eq('Test task')
      end

      it 'respects max_runs safety cap' do
        5.times { |i| task_manager.create(title: "Task #{i}", priority: 1) }

        daemon.start!

        # max_runs is 3, so only 3 should complete
        expect(daemon.runs_completed).to eq(3)
      end

      it 'fires on_task_complete callback' do
        completed_tasks = []
        daemon_with_cb = described_class.new(
          agent_name: 'cb-daemon',
          role: 'test',
          llm_client: llm_client,
          project_root: Dir.pwd,
          task_manager: task_manager,
          mailbox: mailbox,
          max_runs: 1,
          max_cost: 5.0,
          poll_interval: 0.01,
          idle_timeout: 0.05,
          on_task_complete: ->(task, result) { completed_tasks << [task.title, result] }
        )

        task_manager.create(title: 'Callback test', priority: 1)
        daemon_with_cb.start!

        expect(completed_tasks).to eq([['Callback test', 'Task completed successfully']])
      end
    end

    context 'when a task errors' do
      before do
        allow(llm_client).to receive(:chat).and_raise(StandardError, 'LLM exploded')
      end

      it 'releases the task back to pending' do
        task = task_manager.create(title: 'Doomed task', priority: 1)

        daemon.start!

        refreshed = task_manager.get(task.id)
        expect(refreshed.status).to eq('pending')
        expect(refreshed.result).to include('Error: LLM exploded')
      end

      it 'fires on_task_error callback' do
        errored_tasks = []
        daemon_with_cb = described_class.new(
          agent_name: 'err-daemon',
          role: 'test',
          llm_client: llm_client,
          project_root: Dir.pwd,
          task_manager: task_manager,
          mailbox: mailbox,
          max_runs: 1,
          max_cost: 5.0,
          poll_interval: 0.01,
          idle_timeout: 0.05,
          on_task_error: ->(task, error) { errored_tasks << [task.title, error.message] }
        )

        task_manager.create(title: 'Error test', priority: 1)
        daemon_with_cb.start!

        expect(errored_tasks).to eq([['Error test', 'LLM exploded']])
      end
    end

    context 'signal handling' do
      it 'installs INT and TERM signal handlers' do
        expect(Signal).to receive(:trap).with('INT')
        expect(Signal).to receive(:trap).with('TERM')

        daemon.start!
      end
    end
  end
end
