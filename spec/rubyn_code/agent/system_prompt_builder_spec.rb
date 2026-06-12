# frozen_string_literal: true

require 'spec_helper'

# SystemPromptBuilder is a module mixed into Agent::Loop, so its caching
# behavior is exercised through the loop.
RSpec.describe RubynCode::Agent::Loop, 'system prompt caching' do
  let(:llm_client)      { instance_double(RubynCode::LLM::Client) }
  let(:tool_executor)   { instance_double(RubynCode::Tools::Executor, tool_definitions: []) }
  let(:context_manager) do
    instance_double(
      RubynCode::Context::Manager,
      check_compaction!: nil,
      track_usage: nil,
      estimated_tokens: 0,
      needs_compaction?: false,
      advance_turn!: nil
    )
  end
  let(:hook_runner)     { instance_double(RubynCode::Hooks::Runner, fire: nil) }
  let(:conversation)    { RubynCode::Agent::Conversation.new }
  let(:stall_detector)  { RubynCode::Agent::LoopDetector.new }
  let(:system_prompts)  { [] }

  def build_loop(project_root)
    RubynCode::Agent::Loop.new(
      llm_client: llm_client,
      tool_executor: tool_executor,
      context_manager: context_manager,
      hook_runner: hook_runner,
      conversation: conversation,
      permission_tier: RubynCode::Permissions::Tier::UNRESTRICTED,
      stall_detector: stall_detector,
      project_root: project_root
    )
  end

  def text_response(text)
    {
      content: [{ type: 'text', text: text }],
      usage: { input_tokens: 10, output_tokens: 5 },
      stop_reason: 'end_turn'
    }
  end

  def tool_response(name, input, id: 'toolu_1')
    {
      content: [{ type: 'tool_use', id: id, name: name, input: input }],
      usage: { input_tokens: 10, output_tokens: 5 },
      stop_reason: 'tool_use'
    }
  end

  # Captures the system prompt of every LLM call while returning the
  # queued responses in order.
  def stub_chat(*responses)
    queue = responses
    allow(llm_client).to receive(:chat) do |**opts|
      system_prompts << opts[:system]
      queue.shift
    end
  end

  describe 'per-turn caching of static sections' do
    it 'does not rebuild static sections between iterations of the same turn' do
      Dir.mktmpdir do |root|
        File.write(File.join(root, 'RUBYN.md'), 'MARKER-ONE')
        agent_loop = build_loop(root)
        stub_chat(tool_response('read_file', { path: 'x.rb' }), text_response('Done.'))
        # Mutate the instruction file mid-turn — the cached sections must win
        allow(tool_executor).to receive(:execute) do
          File.write(File.join(root, 'RUBYN.md'), 'MARKER-TWO')
          'contents'
        end

        agent_loop.send_message('read x.rb')

        expect(system_prompts.size).to eq(2)
        expect(system_prompts[0]).to include('MARKER-ONE')
        expect(system_prompts[1]).to include('MARKER-ONE')
        expect(system_prompts[1]).not_to include('MARKER-TWO')
      end
    end

    it 'rebuilds static sections at the start of the next turn' do
      Dir.mktmpdir do |root|
        File.write(File.join(root, 'RUBYN.md'), 'MARKER-ONE')
        agent_loop = build_loop(root)
        stub_chat(text_response('Hi.'), text_response('Again.'))

        agent_loop.send_message('hello')
        File.write(File.join(root, 'RUBYN.md'), 'MARKER-TWO')
        agent_loop.send_message('hello again')

        expect(system_prompts[0]).to include('MARKER-ONE')
        expect(system_prompts[1]).to include('MARKER-TWO')
        expect(system_prompts[1]).not_to include('MARKER-ONE')
      end
    end

    it 'still reflects plan mode toggled mid-turn' do
      Dir.mktmpdir do |root|
        File.write(File.join(root, 'RUBYN.md'), 'MARKER-ONE')
        agent_loop = build_loop(root)
        stub_chat(tool_response('read_file', { path: 'x.rb' }), text_response('Done.'))
        allow(tool_executor).to receive(:execute) do
          agent_loop.plan_mode = true
          'contents'
        end

        agent_loop.send_message('read x.rb')

        plan_text = RubynCode::Agent::Prompts::PLAN_MODE_PROMPT
        expect(system_prompts[0]).not_to include(plan_text)
        expect(system_prompts[1]).to include(plan_text)
        expect(system_prompts[1]).to include('MARKER-ONE')
      end
    end

    it 'does not touch memory access counts when building the prompt' do
      Dir.mktmpdir do |root|
        db = setup_test_db_with_tables
        allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)
        store = RubynCode::Memory::Store.new(db, project_path: root)
        store.write(content: 'remember the widget refactor', tier: 'long', category: 'decision')
        agent_loop = build_loop(root)
        stub_chat(text_response('Hi.'))

        agent_loop.send_message('hello')

        expect(system_prompts[0]).to include('remember the widget refactor')
        row = db.query('SELECT access_count FROM memories', []).first
        expect(row['access_count']).to eq(0)
      end
    end
  end
end
