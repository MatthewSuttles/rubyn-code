# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Autonomous::Daemon do
  let(:db) { setup_test_db }
  let(:task_manager) { RubynCode::Tasks::Manager.new(db) }
  let(:llm_client) { instance_double(RubynCode::LLM::Client, model: 'claude-sonnet-4-6') }
  let(:mailbox) { instance_double('Mailbox', pending_for: []) }
  let(:state_changes) { [] }
  let(:session_persistence) { RubynCode::Memory::SessionPersistence.new(db) }

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
      on_state_change: ->(old_s, new_s) { state_changes << [old_s, new_s] },
      session_persistence: session_persistence
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
          %i[spawned working],
          %i[working idle],
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

      it 'releases the task back to pending on first failure with retry count' do
        task = task_manager.create(title: 'Doomed task', priority: 1)

        single_run_daemon = described_class.new(
          agent_name: 'retry-daemon',
          role: 'test',
          llm_client: llm_client,
          project_root: Dir.pwd,
          task_manager: task_manager,
          mailbox: mailbox,
          max_runs: 1,
          max_cost: 5.0,
          poll_interval: 0.01,
          idle_timeout: 0.05
        )
        single_run_daemon.start!

        refreshed = task_manager.get(task.id)
        expect(refreshed.status).to eq('pending')
        expect(refreshed.result).to include('Error (retry 1/3)')
        expect(refreshed.result).to include('LLM exploded')
      end

      it 'marks task as failed after max retries' do
        task = task_manager.create(title: 'Poison task', priority: 1)

        # Pre-set retry count to 2 (one below max)
        task_manager.update(task.id, metadata: JSON.generate({ retry_count: 2 }))

        daemon.start!

        refreshed = task_manager.get(task.id)
        expect(refreshed.status).to eq('failed')
        expect(refreshed.result).to include('Failed after 3 retries')
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

    context 'cost tracking' do
      let(:text_response) do
        RubynCode::LLM::Response.new(
          id: 'msg_test',
          content: [RubynCode::LLM::TextBlock.new(text: 'Done')],
          stop_reason: 'end_turn',
          usage: RubynCode::LLM::Usage.new(input_tokens: 1000, output_tokens: 500)
        )
      end

      before do
        allow(llm_client).to receive(:chat).and_return(text_response)
      end

      it 'accumulates cost using CostCalculator from token counts' do
        task_manager.create(title: 'Cost tracking task', priority: 1)

        daemon.start!

        # With claude-sonnet-4-6 rates: $3/M input + $15/M output
        # 1000 input tokens = $0.003, 500 output tokens = $0.0075
        # Total = $0.0105
        expect(daemon.total_cost).to be > 0.0
        expect(daemon.total_cost).to be_within(0.001).of(0.0105)
      end

      it 'triggers max_cost safety limit' do
        cost_daemon = described_class.new(
          agent_name: 'cost-daemon',
          role: 'test',
          llm_client: llm_client,
          project_root: Dir.pwd,
          task_manager: task_manager,
          mailbox: mailbox,
          max_runs: 100,
          max_cost: 0.001, # Very low cost limit
          poll_interval: 0.01,
          idle_timeout: 0.05
        )

        3.times { |i| task_manager.create(title: "Task #{i}", priority: 1) }

        cost_daemon.start!

        # Should stop after 1 task because cost exceeds limit
        expect(cost_daemon.runs_completed).to eq(1)
        expect(cost_daemon.total_cost).to be > 0.001
      end
    end

    context 'session audit trail' do
      let(:text_response) do
        RubynCode::LLM::Response.new(
          id: 'msg_audit',
          content: [RubynCode::LLM::TextBlock.new(text: 'Audit task done')],
          stop_reason: 'end_turn',
          usage: RubynCode::LLM::Usage.new(input_tokens: 100, output_tokens: 50)
        )
      end

      before do
        allow(llm_client).to receive(:chat).and_return(text_response)
      end

      it 'persists the conversation as a session after task completion' do
        task = task_manager.create(title: 'Audit task', priority: 1)

        daemon.start!

        session_id = "daemon-test-daemon-#{task.id}"
        session = session_persistence.load_session(session_id)
        expect(session).not_to be_nil
        expect(session[:title]).to eq('Daemon: Audit task')
        expect(session[:messages]).not_to be_empty
      end

      it 'does not fail when session_persistence is nil' do
        daemon_no_audit = described_class.new(
          agent_name: 'no-audit',
          role: 'test',
          llm_client: llm_client,
          project_root: Dir.pwd,
          task_manager: task_manager,
          mailbox: mailbox,
          max_runs: 1,
          max_cost: 5.0,
          poll_interval: 0.01,
          idle_timeout: 0.05,
          session_persistence: nil
        )

        task_manager.create(title: 'No audit', priority: 1)

        expect { daemon_no_audit.start! }.not_to raise_error
      end
    end

    context 'signal handling' do
      it 'installs INT and TERM signal handlers' do
        expect(Signal).to receive(:trap).with('INT')
        expect(Signal).to receive(:trap).with('TERM')

        daemon.start!
      end
    end

    context 'multi-turn with tool use' do
      let(:tool_response) do
        RubynCode::LLM::Response.new(
          id: 'msg_tools',
          content: [
            RubynCode::LLM::ToolUseBlock.new(
              id: 'tool_1',
              name: 'read_file',
              input: { 'path' => '/tmp/test.rb' }
            )
          ],
          stop_reason: 'tool_use',
          usage: RubynCode::LLM::Usage.new(input_tokens: 200, output_tokens: 100)
        )
      end

      let(:final_response) do
        RubynCode::LLM::Response.new(
          id: 'msg_final',
          content: [RubynCode::LLM::TextBlock.new(text: 'Read the file and completed the task')],
          stop_reason: 'end_turn',
          usage: RubynCode::LLM::Usage.new(input_tokens: 300, output_tokens: 150)
        )
      end

      before do
        # First call returns tool_use, second call returns text
        allow(llm_client).to receive(:chat).and_return(tool_response, final_response)
      end

      it 'handles tool execution within the agent loop and completes the task' do
        task = task_manager.create(title: 'Multi-turn task', description: 'Read a file', priority: 5)

        daemon.start!

        expect(daemon.runs_completed).to eq(1)
        refreshed = task_manager.get(task.id)
        expect(refreshed.status).to eq('completed')
        expect(refreshed.result).to include('Read the file and completed the task')
      end
    end

    context 'concurrent claiming', :aggregate_failures do
      let(:text_response) do
        RubynCode::LLM::Response.new(
          id: 'msg_concurrent',
          content: [RubynCode::LLM::TextBlock.new(text: 'Done')],
          stop_reason: 'end_turn',
          usage: RubynCode::LLM::Usage.new(input_tokens: 100, output_tokens: 50)
        )
      end

      before do
        allow(llm_client).to receive(:chat).and_return(text_response)
      end

      it 'two daemons claim different tasks and do not double-process' do
        # Create tasks in the shared DB
        task_manager.create(title: 'Task A', priority: 5)
        task_manager.create(title: 'Task B', priority: 5)

        completed_by = Mutex.new
        completions = {}

        daemon_a = described_class.new(
          agent_name: 'daemon-a',
          role: 'test',
          llm_client: llm_client,
          project_root: Dir.pwd,
          task_manager: task_manager,
          mailbox: mailbox,
          max_runs: 1,
          max_cost: 5.0,
          poll_interval: 0.01,
          idle_timeout: 0.05,
          on_task_complete: lambda { |task, _result|
            completed_by.synchronize { completions['daemon-a'] = task.title }
          }
        )

        daemon_b = described_class.new(
          agent_name: 'daemon-b',
          role: 'test',
          llm_client: llm_client,
          project_root: Dir.pwd,
          task_manager: task_manager,
          mailbox: mailbox,
          max_runs: 1,
          max_cost: 5.0,
          poll_interval: 0.01,
          idle_timeout: 0.05,
          on_task_complete: lambda { |task, _result|
            completed_by.synchronize { completions['daemon-b'] = task.title }
          }
        )

        threads = [
          Thread.new { daemon_a.start! },
          Thread.new { daemon_b.start! }
        ]
        threads.each(&:join)

        # Both daemons should have completed one task each
        expect(completions.size).to eq(2)

        # They should have claimed different tasks
        task_titles = completions.values
        expect(task_titles).to contain_exactly('Task A', 'Task B')

        # All tasks should be completed
        all_completed = task_manager.list(status: 'completed')
        expect(all_completed.length).to eq(2)
      end
    end
  end
end
