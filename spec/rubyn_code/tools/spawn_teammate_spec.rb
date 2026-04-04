# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::Tools::SpawnTeammate do
  let(:llm_client) { instance_double('LLMClient') }
  let(:status_calls) { [] }
  let(:on_status) { ->(type, msg) { status_calls << [type, msg] } }
  let(:db) { setup_test_db }

  def make_text_response(text)
    text_block = instance_double('TextBlock', type: 'text', text: text)
    instance_double('Response', content: [text_block], stop_reason: 'end_turn')
  end

  def make_tool_response(tool_name, input, id: 'tool_123')
    tool_block = instance_double(
      'ToolUseBlock',
      type: 'tool_use',
      name: tool_name,
      input: input,
      id: id
    )
    instance_double('Response', content: [tool_block], stop_reason: 'tool_use')
  end

  def build_tool(dir)
    tool = described_class.new(project_root: dir)
    tool.llm_client = llm_client
    tool.on_status = on_status
    tool.db = db
    tool
  end

  before do
    # Ensure Teams tables exist
    db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS teammates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        role TEXT NOT NULL,
        persona TEXT,
        model TEXT,
        status TEXT NOT NULL DEFAULT 'idle',
        metadata TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL
      )
    SQL
    db.execute(<<~SQL)
      CREATE UNIQUE INDEX IF NOT EXISTS idx_teammates_name ON teammates (name)
    SQL
    db.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS mailbox_messages (
        id TEXT PRIMARY KEY,
        sender TEXT NOT NULL,
        recipient TEXT NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'message',
        payload TEXT NOT NULL,
        read INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
      )
    SQL
    db.execute(<<~SQL)
      CREATE INDEX IF NOT EXISTS idx_mailbox_recipient_read
      ON mailbox_messages (recipient, read)
    SQL

    allow(RubynCode::Tools::Registry).to receive(:tool_definitions).and_return([
      { name: 'read_file', description: 'Read a file', input_schema: {} },
      { name: 'glob', description: 'Glob files', input_schema: {} },
      { name: 'spawn_agent', description: 'Spawn agent', input_schema: {} },
      { name: 'spawn_teammate', description: 'Spawn teammate', input_schema: {} },
      { name: 'send_message', description: 'Send message', input_schema: {} },
      { name: 'read_inbox', description: 'Read inbox', input_schema: {} },
      { name: 'compact', description: 'Compact', input_schema: {} }
    ])
  end

  describe '#execute' do
    context 'when llm_client is not set' do
      it 'raises Error' do
        with_temp_project do |dir|
          tool = described_class.new(project_root: dir)
          tool.db = db

          expect { tool.execute(name: 'tester', role: 'tester', prompt: 'Test it') }
            .to raise_error(RubynCode::Error, 'LLM client not available')
        end
      end
    end

    context 'when db is not set' do
      it 'raises Error' do
        with_temp_project do |dir|
          tool = described_class.new(project_root: dir)
          tool.llm_client = llm_client

          expect { tool.execute(name: 'tester', role: 'tester', prompt: 'Test it') }
            .to raise_error(RubynCode::Error, 'Database not available')
        end
      end
    end

    context 'when both dependencies are set' do
      it 'returns a spawn confirmation message' do
        with_temp_project do |dir|
          allow(llm_client).to receive(:chat).and_return(make_text_response('Done.'))

          tool = build_tool(dir)
          result = tool.execute(name: 'alice', role: 'coder', prompt: 'Write tests')

          expect(result).to include("Spawned teammate 'alice' as coder")
          expect(result).to include('Write tests')
        end
      end

      it 'truncates long prompts in the return message' do
        with_temp_project do |dir|
          allow(llm_client).to receive(:chat).and_return(make_text_response('Done.'))

          tool = build_tool(dir)
          long_prompt = 'x' * 200
          result = tool.execute(name: 'bob', role: 'reviewer', prompt: long_prompt)

          expect(result).to include('x' * 101)
          expect(result.length).to be < 200
        end
      end

      it 'calls the status callback with :started' do
        with_temp_project do |dir|
          allow(llm_client).to receive(:chat).and_return(make_text_response('Done.'))

          tool = build_tool(dir)
          tool.execute(name: 'charlie', role: 'tester', prompt: 'Run specs')

          # Give thread a moment to start
          sleep 0.1

          expect(status_calls).to include([:started, "Spawning teammate 'charlie' as tester..."])
        end
      end

      it 'spawns a background thread for the agent' do
        with_temp_project do |dir|
          allow(llm_client).to receive(:chat).and_return(make_text_response('All done'))

          tool = build_tool(dir)

          thread_created = false
          allow(Thread).to receive(:new) do |&block|
            thread_created = true
            # Don't actually run the block in tests
          end

          tool.execute(name: 'dave', role: 'coder', prompt: 'Code stuff')
          expect(thread_created).to be true
        end
      end
    end

    context 'when using default_status callback' do
      it 'uses Debug.agent when no on_status is set' do
        with_temp_project do |dir|
          tool = described_class.new(project_root: dir)
          tool.llm_client = llm_client
          tool.db = db

          allow(llm_client).to receive(:chat).and_return(make_text_response('Done'))
          allow(RubynCode::Debug).to receive(:agent)
          allow(Thread).to receive(:new)

          tool.execute(name: 'eve', role: 'tester', prompt: 'Test')

          expect(RubynCode::Debug).to have_received(:agent).with("spawn_teammate: Spawning teammate 'eve' as tester...")
        end
      end
    end
  end

  describe 'tools_for_teammate (private, exercised through execute)' do
    it 'filters out blocked tools' do
      with_temp_project do |dir|
        chat_args = nil
        allow(llm_client).to receive(:chat) do |**kwargs|
          chat_args = kwargs
          make_text_response('Done.')
        end

        # Need to actually run the thread body to capture chat args
        allow(Thread).to receive(:new) do |&block|
          block.call
        end

        # Suppress poll_inbox from looping
        tool = build_tool(dir)
        allow(tool).to receive(:sleep)
        allow(RubynCode::Debug).to receive(:agent)

        tool.execute(name: 'filter_test', role: 'coder', prompt: 'Test')

        tool_names = chat_args[:tools].map { |t| t[:name] }
        expect(tool_names).to include('read_file', 'glob')
        expect(tool_names).not_to include('spawn_agent', 'spawn_teammate', 'send_message', 'read_inbox', 'compact')
      end
    end
  end

  describe 'execute_tool_calls (private, exercised through thread)' do
    it 'blocks recursive agent spawning' do
      with_temp_project do |dir|
        spawn_response = make_tool_response('spawn_agent', { 'prompt' => 'recursive' }, id: 'tc_spawn')
        text_response = make_text_response('Finished.')

        call_count = 0
        allow(llm_client).to receive(:chat) do |**_kwargs|
          call_count += 1
          call_count == 1 ? spawn_response : text_response
        end

        allow(Thread).to receive(:new) do |&block|
          block.call
        end

        tool = build_tool(dir)
        allow(tool).to receive(:sleep)
        allow(RubynCode::Debug).to receive(:agent)

        tool.execute(name: 'recurse_test', role: 'coder', prompt: 'Try recursion')

        # The test passes if no infinite loop or error occurred
        expect(status_calls.map(&:first)).to include(:tool)
      end
    end

    it 'handles tool execution errors gracefully' do
      with_temp_project do |dir|
        tool_response = make_tool_response('read_file', { 'path' => 'nonexistent.rb' }, id: 'tc_err')
        text_response = make_text_response('Error handled.')

        call_count = 0
        allow(llm_client).to receive(:chat) do |**_kwargs|
          call_count += 1
          call_count == 1 ? tool_response : text_response
        end

        allow(Thread).to receive(:new) do |&block|
          block.call
        end

        allow(RubynCode::Tools::Registry).to receive(:get).with('read_file').and_raise(
          RubynCode::ToolNotFoundError, 'Unknown tool: read_file'
        )

        tool = build_tool(dir)
        allow(tool).to receive(:sleep)
        allow(RubynCode::Debug).to receive(:agent)

        tool.execute(name: 'error_test', role: 'coder', prompt: 'Read file')

        expect(status_calls.map(&:first)).to include(:tool)
      end
    end
  end

  describe 'run_teammate_agent error handling (private)' do
    it 'catches errors and reports via callback' do
      with_temp_project do |dir|
        allow(llm_client).to receive(:chat).and_raise(StandardError, 'LLM failure')

        allow(Thread).to receive(:new) do |&block|
          block.call
        end

        tool = build_tool(dir)
        allow(RubynCode::Debug).to receive(:agent)

        tool.execute(name: 'crash_test', role: 'coder', prompt: 'Crash')

        done_calls = status_calls.select { |type, _| type == :done }
        expect(done_calls.last&.last).to include('error: LLM failure')
      end
    end

    it 'reports when iteration limit is reached' do
      with_temp_project do |dir|
        stub_const('RubynCode::Config::Defaults::MAX_SUB_AGENT_ITERATIONS', 1)

        tool_response = make_tool_response('glob', { 'pattern' => '*.rb' }, id: 'tc_limit')

        allow(llm_client).to receive(:chat).and_return(tool_response)

        allow(Thread).to receive(:new) do |&block|
          block.call
        end

        # Stub Registry.get so the tool call succeeds
        fake_tool_class = Class.new(RubynCode::Tools::Base) do
          const_set(:TOOL_NAME, 'glob')
          const_set(:DESCRIPTION, 'Glob')
          const_set(:PARAMETERS, {}.freeze)
          const_set(:RISK_LEVEL, :read)
          define_method(:execute) { |**_| 'results' }
        end
        allow(RubynCode::Tools::Registry).to receive(:get).with('glob').and_return(fake_tool_class)

        tool = build_tool(dir)
        allow(RubynCode::Debug).to receive(:agent)

        tool.execute(name: 'limit_test', role: 'coder', prompt: 'Loop forever')

        done_calls = status_calls.select { |type, _| type == :done }
        expect(done_calls.last&.last).to include('reached iteration limit')
      end
    end
  end

  describe '.tool_name' do
    it 'returns spawn_teammate' do
      expect(described_class.tool_name).to eq('spawn_teammate')
    end
  end

  describe '.risk_level' do
    it 'is execute' do
      expect(described_class.risk_level).to eq(:execute)
    end
  end
end
