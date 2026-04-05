# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::REPL do
  # ── Shared stubs for expensive external boundaries ──────────────────
  let(:db) do
    instance_double(
      RubynCode::DB::Connection,
      execute: nil,
      query: []
    )
  end
  let(:migrator) { instance_double(RubynCode::DB::Migrator, migrate!: nil) }
  let(:llm_client) do
    # Use a plain object with the methods the REPL expects, because
    # LLM::Client doesn't define model= natively — the REPL guards with respond_to?.
    obj = Object.new
    obj.define_singleton_method(:chat) { |**_| nil }
    obj.define_singleton_method(:model=) { |_m| nil }
    obj
  end
  let(:session_persistence) do
    instance_double(
      RubynCode::Memory::SessionPersistence,
      save_session: nil,
      load_session: nil
    )
  end
  let(:budget_enforcer) do
    instance_double(RubynCode::Observability::BudgetEnforcer)
  end
  let(:background_worker) do
    instance_double(RubynCode::Background::Worker, shutdown!: nil)
  end
  let(:agent_loop) do
    instance_double(RubynCode::Agent::Loop, send_message: 'response text').tap do |al|
      allow(al).to receive(:plan_mode=)
    end
  end

  before do
    # DB boundary
    allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)
    allow(RubynCode::DB::Migrator).to receive(:new).and_return(migrator)

    # Auth boundary
    allow(RubynCode::Auth::TokenStore).to receive(:valid?).and_return(true)
    allow(RubynCode::Auth::TokenStore).to receive(:load).and_return({ source: :api_key })

    # LLM boundary
    allow(RubynCode::LLM::Client).to receive(:new).and_return(llm_client)

    # Heavy components that touch the filesystem or DB in their constructors
    allow(RubynCode::Observability::BudgetEnforcer).to receive(:new).and_return(budget_enforcer)
    allow(RubynCode::Memory::SessionPersistence).to receive(:new).and_return(session_persistence)
    allow(RubynCode::Background::Worker).to receive(:new).and_return(background_worker)
    allow(RubynCode::Agent::Loop).to receive(:new).and_return(agent_loop)

    # Hooks — these scan the filesystem
    allow(RubynCode::Hooks::BuiltIn).to receive(:register_all!)
    allow(RubynCode::Hooks::UserHooks).to receive(:load!)

    # Tools::Executor calls Registry.load_all! which requires all tool files
    allow(RubynCode::Tools::Executor).to receive(:new).and_return(
      instance_double(
        RubynCode::Tools::Executor,
        'llm_client=': nil,
        'background_worker=': nil,
        'db=': nil,
        'on_agent_status=': nil,
        'ask_user_callback=': nil,
        tool_definitions: []
      )
    )

    # Skills — touches filesystem
    allow(RubynCode::Skills::Catalog).to receive(:new).and_return(
      instance_double(RubynCode::Skills::Catalog)
    )
    allow(RubynCode::Skills::Loader).to receive(:new).and_return(
      instance_double(RubynCode::Skills::Loader)
    )

    # Readline setup
    allow(Reline).to receive(:completion_proc=)
    allow(Reline).to receive(:completion_append_character=)

    # Filesystem
    allow(FileUtils).to receive(:mkdir_p)
    allow(Dir).to receive(:exist?).and_call_original
    allow(Dir).to receive(:exist?).with(RubynCode::Config::Defaults::HOME_DIR).and_return(true)

    # Suppress all output
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
    allow($stdout).to receive(:write).and_return(0)
  end

  # Helper to build a REPL instance with defaults
  def build_repl(**opts)
    described_class.new(project_root: Dir.pwd, **opts)
  end

  # ── Initialization ──────────────────────────────────────────────────

  describe '#initialize' do
    it 'sets permission_tier to :allow_read by default' do
      repl = build_repl
      expect(repl.instance_variable_get(:@permission_tier)).to eq(:allow_read)
    end

    it 'sets permission_tier to :unrestricted in yolo mode' do
      repl = build_repl(yolo: true)
      expect(repl.instance_variable_get(:@permission_tier)).to eq(:unrestricted)
    end

    it 'creates all required components' do
      repl = build_repl

      expect(repl.instance_variable_get(:@db)).to eq(db)
      expect(repl.instance_variable_get(:@llm_client)).to eq(llm_client)
      expect(repl.instance_variable_get(:@agent_loop)).to eq(agent_loop)
      expect(repl.instance_variable_get(:@session_persistence)).to eq(session_persistence)
      expect(repl.instance_variable_get(:@conversation)).to be_a(RubynCode::Agent::Conversation)
      expect(repl.instance_variable_get(:@command_registry)).to be_a(RubynCode::CLI::Commands::Registry)
    end

    it 'starts with plan_mode disabled' do
      repl = build_repl
      expect(repl.instance_variable_get(:@plan_mode)).to be false
    end

    it 'starts in running state' do
      repl = build_repl
      expect(repl.instance_variable_get(:@running)).to be true
    end

    it 'generates a session_id when none is provided' do
      repl = build_repl
      # session_id is lazily generated via current_session_id, so trigger it
      sid = repl.send(:current_session_id)
      expect(sid).to be_a(String)
      expect(sid.length).to eq(32)
    end

    it 'uses the provided session_id' do
      repl = build_repl(session_id: 'abc123')
      expect(repl.instance_variable_get(:@session_id)).to eq('abc123')
    end
  end

  # ── Command Dispatching (handle_command) ────────────────────────────

  describe '#handle_command' do
    subject(:repl) { build_repl }

    let(:command_class) { RubynCode::CLI::InputHandler::Command }

    it 'sets running to false for :quit' do
      repl.send(:handle_command, command_class.new(action: :quit, args: []))
      expect(repl.instance_variable_get(:@running)).to be false
    end

    it 'calls handle_message for :message' do
      allow(repl).to receive(:handle_message)
      repl.send(:handle_command, command_class.new(action: :message, args: ['hello']))
      expect(repl).to have_received(:handle_message).with('hello')
    end

    it 'does nothing for :empty' do
      expect {
        repl.send(:handle_command, command_class.new(action: :empty, args: []))
      }.not_to raise_error
    end

    it 'calls display_commands for :list_commands' do
      allow(repl).to receive(:display_commands)
      repl.send(:handle_command, command_class.new(action: :list_commands, args: []))
      expect(repl).to have_received(:display_commands)
    end

    it 'shows a warning for :unknown_command' do
      renderer = repl.instance_variable_get(:@renderer)
      allow(renderer).to receive(:warning)

      repl.send(:handle_command, command_class.new(action: :unknown_command, args: ['/bogus']))

      expect(renderer).to have_received(:warning).with(/Unknown command.*\/bogus/)
    end

    it 'dispatches :slash_command through the command registry' do
      allow(repl).to receive(:dispatch_slash_command)
      repl.send(:handle_command, command_class.new(action: :slash_command, args: ['/help']))
      expect(repl).to have_received(:dispatch_slash_command).with('/help', [])
    end
  end

  # ── handle_command_result ───────────────────────────────────────────

  describe '#handle_command_result' do
    subject(:repl) { build_repl }

    it 'updates plan_mode when :set_plan_mode' do
      repl.send(:handle_command_result, { action: :set_plan_mode, enabled: true })
      expect(repl.instance_variable_get(:@plan_mode)).to be true
      expect(agent_loop).to have_received(:plan_mode=).with(true)
    end

    it 'updates llm_client model when :set_model' do
      renderer = repl.instance_variable_get(:@renderer)
      allow(renderer).to receive(:info)
      allow(llm_client).to receive(:model=)

      repl.send(:handle_command_result, { action: :set_model, model: 'claude-haiku' })
      expect(llm_client).to have_received(:model=).with('claude-haiku')
    end

    it 'creates a new budget enforcer when :set_budget' do
      new_enforcer = instance_double(RubynCode::Observability::BudgetEnforcer)
      allow(RubynCode::Observability::BudgetEnforcer).to receive(:new).and_return(new_enforcer)

      repl.send(:handle_command_result, { action: :set_budget, amount: 20.0 })

      expect(RubynCode::Observability::BudgetEnforcer).to have_received(:new).with(
        db,
        hash_including(session_limit: 20.0)
      )
      expect(repl.instance_variable_get(:@budget_enforcer)).to eq(new_enforcer)
    end

    it 'updates session_id when :set_session_id' do
      repl.send(:handle_command_result, { action: :set_session_id, session_id: 'new-session' })
      expect(repl.instance_variable_get(:@session_id)).to eq('new-session')
    end

    it 'ignores unknown result hashes' do
      expect {
        repl.send(:handle_command_result, { action: :unknown_thing })
      }.not_to raise_error
    end
  end

  # ── handle_message ──────────────────────────────────────────────────

  describe '#handle_message' do
    subject(:repl) { build_repl }

    let(:spinner) { repl.instance_variable_get(:@spinner) }
    let(:renderer) { repl.instance_variable_get(:@renderer) }

    before do
      allow(spinner).to receive(:start)
      allow(spinner).to receive(:stop)
      allow(spinner).to receive(:error)
      allow(renderer).to receive(:display)
      allow(renderer).to receive(:error)
    end

    it 'starts spinner, sends message through agent_loop, and displays the response' do
      repl.send(:handle_message, 'hello world')

      expect(spinner).to have_received(:start)
      expect(agent_loop).to have_received(:send_message).with('hello world')
      expect(spinner).to have_received(:stop)
      expect(session_persistence).to have_received(:save_session)
    end

    it 'displays the response when no streaming occurred' do
      repl.send(:handle_message, 'hello world')
      expect(renderer).to have_received(:display).with('response text')
    end

    it 'catches BudgetExceededError and shows error' do
      allow(agent_loop).to receive(:send_message).and_raise(
        RubynCode::BudgetExceededError, 'over limit'
      )

      repl.send(:handle_message, 'expensive request')

      expect(spinner).to have_received(:error)
      expect(renderer).to have_received(:error).with(/Budget exceeded.*over limit/)
    end

    it 'catches generic StandardError and shows error' do
      allow(agent_loop).to receive(:send_message).and_raise(
        StandardError, 'something broke'
      )

      repl.send(:handle_message, 'bad request')

      expect(spinner).to have_received(:error)
      expect(renderer).to have_received(:error).with(/Error.*something broke/)
    end
  end

  # ── shutdown! ───────────────────────────────────────────────────────

  describe '#shutdown!' do
    subject(:repl) { build_repl }

    let(:spinner) { repl.instance_variable_get(:@spinner) }
    let(:renderer) { repl.instance_variable_get(:@renderer) }
    let(:conversation) { repl.instance_variable_get(:@conversation) }

    before do
      # GOODBYE_MESSAGES is defined on REPL but referenced from
      # ReplLifecycle; surface it so the module's constant lookup succeeds.
      unless RubynCode::CLI::ReplLifecycle.const_defined?(:GOODBYE_MESSAGES, false)
        RubynCode::CLI::ReplLifecycle.const_set(
          :GOODBYE_MESSAGES, RubynCode::CLI::REPL::GOODBYE_MESSAGES
        )
      end

      allow(spinner).to receive(:stop)
      allow(renderer).to receive(:info)
      allow(renderer).to receive(:success)
      allow(RubynCode::Learning::InstinctMethods).to receive(:decay_all)
    end

    it 'saves the session' do
      repl.send(:shutdown!)
      expect(session_persistence).to have_received(:save_session)
    end

    it 'is idempotent — only runs once' do
      repl.send(:shutdown!)
      repl.send(:shutdown!)

      expect(session_persistence).to have_received(:save_session).once
    end

    it 'extracts learnings when conversation has more than 5 messages' do
      6.times { |i| conversation.add_user_message("message #{i}") }

      allow(RubynCode::Learning::Extractor).to receive(:call)

      repl.send(:shutdown!)

      expect(RubynCode::Learning::Extractor).to have_received(:call).with(
        conversation.messages,
        llm_client: llm_client,
        project_path: Dir.pwd
      )
    end

    it 'skips learning extraction for short conversations' do
      conversation.add_user_message('only one message')

      allow(RubynCode::Learning::Extractor).to receive(:call)

      repl.send(:shutdown!)

      expect(RubynCode::Learning::Extractor).not_to have_received(:call)
    end

    it 'runs instinct decay' do
      repl.send(:shutdown!)

      expect(RubynCode::Learning::InstinctMethods).to have_received(:decay_all).with(
        db,
        project_path: Dir.pwd
      )
    end

    it 'shuts down the background worker' do
      repl.send(:shutdown!)
      expect(background_worker).to have_received(:shutdown!)
    end

    it 'handles errors during learning extraction gracefully' do
      6.times { |i| conversation.add_user_message("message #{i}") }

      allow(RubynCode::Learning::Extractor).to receive(:call).and_raise(
        StandardError, 'extraction failed'
      )

      expect { repl.send(:shutdown!) }.not_to raise_error
    end

    it 'handles errors during instinct decay gracefully' do
      allow(RubynCode::Learning::InstinctMethods).to receive(:decay_all).and_raise(
        StandardError, 'decay failed'
      )

      expect { repl.send(:shutdown!) }.not_to raise_error
    end
  end

  # ── run loop ────────────────────────────────────────────────────────

  describe '#run' do
    subject(:repl) { build_repl }

    let(:spinner) { repl.instance_variable_get(:@spinner) }
    let(:renderer) { repl.instance_variable_get(:@renderer) }
    let(:version_check) do
      instance_double(RubynCode::CLI::VersionCheck, start: nil, notify: nil)
    end

    before do
      unless RubynCode::CLI::ReplLifecycle.const_defined?(:GOODBYE_MESSAGES, false)
        RubynCode::CLI::ReplLifecycle.const_set(
          :GOODBYE_MESSAGES, RubynCode::CLI::REPL::GOODBYE_MESSAGES
        )
      end

      allow(RubynCode::CLI::VersionCheck).to receive(:new).and_return(version_check)
      allow(spinner).to receive(:stop)
      allow(renderer).to receive(:welcome)
      allow(renderer).to receive(:info)
      allow(renderer).to receive(:success)
      allow(renderer).to receive(:prompt).and_return('rubyn> ')
      allow(RubynCode::Learning::InstinctMethods).to receive(:decay_all)
    end

    it 'breaks the loop on nil input (Ctrl-D)' do
      allow(Reline).to receive(:readline).and_return(nil)

      repl.run

      expect(session_persistence).to have_received(:save_session)
    end

    it 'shows welcome message and starts version check' do
      allow(Reline).to receive(:readline).and_return(nil)

      repl.run

      expect(version_check).to have_received(:start)
      expect(renderer).to have_received(:welcome)
      expect(version_check).to have_received(:notify)
    end

    it 'exits on /quit command' do
      allow(Reline).to receive(:readline).and_return('/quit', nil)

      repl.run

      expect(session_persistence).to have_received(:save_session)
    end

    it 'processes messages through the agent loop' do
      allow(Reline).to receive(:readline).and_return('hello', nil)
      allow(agent_loop).to receive(:send_message).and_return('hi back')
      allow(spinner).to receive(:start)
      allow(renderer).to receive(:display)

      repl.run

      expect(agent_loop).to have_received(:send_message).with('hello')
    end

    it 'shows hint on single Ctrl-C' do
      call_count = 0
      allow(Reline).to receive(:readline) do
        call_count += 1
        if call_count == 1
          raise Interrupt
        else
          nil # exit on next iteration
        end
      end

      repl.run

      expect(renderer).to have_received(:info).with(/Ctrl-C.*exit.*\/quit/)
    end

    it 'exits on double Ctrl-C within 2 seconds' do
      call_count = 0
      allow(Reline).to receive(:readline) do
        call_count += 1
        raise Interrupt
      end

      repl.run

      # The loop should have exited after two rapid interrupts
      expect(session_persistence).to have_received(:save_session)
    end

    it 'handles multiple inputs in sequence' do
      inputs = ['first message', 'second message', '/quit']
      allow(Reline).to receive(:readline).and_return(*inputs)
      allow(agent_loop).to receive(:send_message).and_return('response')
      allow(spinner).to receive(:start)
      allow(renderer).to receive(:display)

      repl.run

      expect(agent_loop).to have_received(:send_message).twice
    end
  end

  # ── dispatch_slash_command ──────────────────────────────────────────

  describe '#dispatch_slash_command' do
    subject(:repl) { build_repl }

    let(:renderer) { repl.instance_variable_get(:@renderer) }
    let(:command_registry) { repl.instance_variable_get(:@command_registry) }

    before do
      allow(renderer).to receive(:warning)
      allow(renderer).to receive(:info)
    end

    it 'sets running to false when command returns :quit' do
      allow(command_registry).to receive(:dispatch).and_return(:quit)

      repl.send(:dispatch_slash_command, '/quit', [])

      expect(repl.instance_variable_get(:@running)).to be false
    end

    it 'shows warning for :unknown commands' do
      allow(command_registry).to receive(:dispatch).and_return(:unknown)

      repl.send(:dispatch_slash_command, '/nonexistent', [])

      expect(renderer).to have_received(:warning).with(/Unknown command/)
    end

    it 'delegates hash results to handle_command_result' do
      allow(command_registry).to receive(:dispatch).and_return(
        { action: :set_plan_mode, enabled: true }
      )

      repl.send(:dispatch_slash_command, '/plan', [])

      expect(repl.instance_variable_get(:@plan_mode)).to be true
    end
  end

  # ── Authentication ──────────────────────────────────────────────────

  describe 'authentication' do
    it 'exits with status 1 when not authenticated' do
      allow(RubynCode::Auth::TokenStore).to receive(:load_for_provider).and_return(nil)

      renderer = instance_double(RubynCode::CLI::Renderer)
      allow(RubynCode::CLI::Renderer).to receive(:new).and_return(renderer)
      allow(renderer).to receive(:yolo=)
      allow(renderer).to receive(:error)
      allow(renderer).to receive(:info)

      expect {
        build_repl
      }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end
  end
end
