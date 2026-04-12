# frozen_string_literal: true

require 'spec_helper'
require 'reline'

RSpec.describe 'REPL MCP integration' do
  let(:db) do
    instance_double(
      RubynCode::DB::Connection,
      execute: nil,
      query: []
    )
  end
  let(:migrator) { instance_double(RubynCode::DB::Migrator, migrate!: nil) }
  let(:llm_client) do
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

  let(:mcp_transport) do
    instance_double(
      'Transport',
      start!: nil,
      stop!: nil,
      alive?: true,
      send_notification: nil
    )
  end
  let(:mcp_client) do
    instance_double(
      RubynCode::MCP::Client,
      name: 'test-server',
      connect!: nil,
      disconnect!: nil,
      connected?: true,
      tools: [{ 'name' => 'test_tool', 'description' => 'A test tool' }]
    )
  end

  before do
    # DB boundary
    allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)
    allow(RubynCode::DB::Migrator).to receive(:new).and_return(migrator)

    # Auth boundary
    allow(RubynCode::Auth::TokenStore).to receive(:valid_for?).with('anthropic').and_return(true)
    allow(RubynCode::Auth::TokenStore).to receive(:load_for_provider).with('anthropic').and_return({ source: :api_key })

    # LLM boundary
    allow(RubynCode::LLM::Client).to receive(:new).and_return(llm_client)

    # Heavy components
    allow(RubynCode::Observability::BudgetEnforcer).to receive(:new).and_return(budget_enforcer)
    allow(RubynCode::Memory::SessionPersistence).to receive(:new).and_return(session_persistence)
    allow(RubynCode::Background::Worker).to receive(:new).and_return(background_worker)
    allow(RubynCode::Agent::Loop).to receive(:new).and_return(agent_loop)

    # Hooks
    allow(RubynCode::Hooks::BuiltIn).to receive(:register_all!)
    allow(RubynCode::Hooks::UserHooks).to receive(:load!)

    # Tools::Executor
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

    # Skills
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

    # Suppress output
    allow($stdout).to receive(:puts)
    allow($stdout).to receive(:print)
    allow($stdout).to receive(:write).and_return(0)
  end

  after do
    RubynCode::Tools::Registry.instance_variable_get(:@tools)&.delete_if { |k, _| k.start_with?('mcp_') }
  end

  def build_repl(**opts)
    RubynCode::CLI::REPL.new(project_root: Dir.pwd, **opts)
  end

  describe 'setup_mcp_servers!' do
    context 'when no mcp.json exists' do
      before do
        allow(RubynCode::MCP::Config).to receive(:load).and_return([])
      end

      it 'initializes @mcp_clients as empty array' do
        repl = build_repl
        expect(repl.instance_variable_get(:@mcp_clients)).to eq([])
      end

      it 'does not create any MCP clients' do
        expect(RubynCode::MCP::Client).not_to receive(:from_config)
        build_repl
      end
    end

    context 'when mcp.json has server configurations' do
      let(:server_configs) do
        [
          { name: 'github', command: 'npx', args: ['-y', '@mcp/server-github'], env: {} }
        ]
      end

      before do
        allow(RubynCode::MCP::Config).to receive(:load).and_return(server_configs)
        allow(RubynCode::MCP::Client).to receive(:from_config).and_return(mcp_client)
        allow(RubynCode::MCP::ToolBridge).to receive(:bridge).and_return([])
      end

      it 'creates and connects MCP clients' do
        build_repl

        expect(RubynCode::MCP::Client).to have_received(:from_config).with(server_configs.first)
        expect(mcp_client).to have_received(:connect!)
      end

      it 'bridges discovered tools' do
        build_repl

        expect(RubynCode::MCP::ToolBridge).to have_received(:bridge).with(mcp_client)
      end

      it 'stores connected clients in @mcp_clients' do
        repl = build_repl

        expect(repl.instance_variable_get(:@mcp_clients)).to eq([mcp_client])
      end
    end

    context 'when a server fails to connect' do
      let(:server_configs) do
        [
          { name: 'broken', command: 'nonexistent', args: [], env: {} },
          { name: 'working', command: 'npx', args: [], env: {} }
        ]
      end

      let(:working_client) do
        instance_double(
          RubynCode::MCP::Client,
          name: 'working',
          connect!: nil,
          disconnect!: nil,
          connected?: true,
          tools: []
        )
      end

      before do
        allow(RubynCode::MCP::Config).to receive(:load).and_return(server_configs)

        broken_client = instance_double(RubynCode::MCP::Client, name: 'broken')
        allow(broken_client).to receive(:connect!).and_raise(
          RubynCode::MCP::Client::ClientError, 'connection refused'
        )

        allow(RubynCode::MCP::Client).to receive(:from_config).with(server_configs[0]).and_return(broken_client)
        allow(RubynCode::MCP::Client).to receive(:from_config).with(server_configs[1]).and_return(working_client)
        allow(RubynCode::MCP::ToolBridge).to receive(:bridge).and_return([])
      end

      it 'warns about the broken server but does not crash' do
        expect { build_repl }.not_to raise_error
      end

      it 'still connects the working server' do
        repl = build_repl

        expect(repl.instance_variable_get(:@mcp_clients)).to eq([working_client])
      end
    end
  end

  describe 'disconnect_mcp_clients!' do
    let(:server_configs) do
      [{ name: 'test-server', command: 'npx', args: [], env: {} }]
    end

    before do
      allow(RubynCode::MCP::Config).to receive(:load).and_return(server_configs)
      allow(RubynCode::MCP::Client).to receive(:from_config).and_return(mcp_client)
      allow(RubynCode::MCP::ToolBridge).to receive(:bridge).and_return([])
    end

    it 'disconnects all MCP clients on explicit call' do
      repl = build_repl
      repl.send(:disconnect_mcp_clients!)

      expect(mcp_client).to have_received(:disconnect!)
    end

    it 'clears the clients list after disconnect' do
      repl = build_repl
      repl.send(:disconnect_mcp_clients!)

      expect(repl.instance_variable_get(:@mcp_clients)).to be_empty
    end

    it 'handles disconnect errors gracefully' do
      allow(mcp_client).to receive(:disconnect!).and_raise(StandardError, 'already gone')

      repl = build_repl

      expect { repl.send(:disconnect_mcp_clients!) }.not_to raise_error
    end
  end

  describe 'shutdown! disconnects MCP clients' do
    let(:server_configs) do
      [{ name: 'test-server', command: 'npx', args: [], env: {} }]
    end

    before do
      allow(RubynCode::MCP::Config).to receive(:load).and_return(server_configs)
      allow(RubynCode::MCP::Client).to receive(:from_config).and_return(mcp_client)
      allow(RubynCode::MCP::ToolBridge).to receive(:bridge).and_return([])

      unless RubynCode::CLI::ReplLifecycle.const_defined?(:GOODBYE_MESSAGES, false)
        RubynCode::CLI::ReplLifecycle.const_set(
          :GOODBYE_MESSAGES, RubynCode::CLI::REPL::GOODBYE_MESSAGES
        )
      end

      allow(RubynCode::Learning::InstinctMethods).to receive(:decay_all)
    end

    it 'disconnects MCP clients during shutdown' do
      repl = build_repl
      repl.send(:shutdown!)

      expect(mcp_client).to have_received(:disconnect!)
    end
  end
end
