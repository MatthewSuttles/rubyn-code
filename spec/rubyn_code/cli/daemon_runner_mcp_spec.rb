# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'DaemonRunner MCP integration' do
  let(:db) { setup_test_db }
  let(:llm_client) { instance_double(RubynCode::LLM::Client) }
  let(:renderer) { instance_double(RubynCode::CLI::Renderer) }

  let(:options) do
    {
      command: :daemon,
      daemon: {
        agent_name: 'test-daemon',
        role: 'test agent',
        max_runs: 1,
        max_cost: 1.0,
        idle_timeout: 0.05,
        poll_interval: 0.01
      }
    }
  end

  let(:mcp_client) do
    instance_double(
      RubynCode::MCP::Client,
      name: 'test-server',
      connect!: nil,
      disconnect!: nil,
      connected?: true,
      tools: [{ 'name' => 'remote_tool', 'description' => 'A remote tool' }]
    )
  end

  before do
    allow(RubynCode::CLI::Renderer).to receive(:new).and_return(renderer)
    allow(renderer).to receive(:info)
    allow(renderer).to receive(:success)
    allow(renderer).to receive(:error)

    # Stub infrastructure
    allow(RubynCode::Auth::TokenStore).to receive(:valid?).and_return(true)
    allow(RubynCode::LLM::Client).to receive(:new).and_return(llm_client)
    allow(RubynCode::DB::Connection).to receive(:instance).and_return(db)

    migrator = instance_double(RubynCode::DB::Migrator)
    allow(RubynCode::DB::Migrator).to receive(:new).and_return(migrator)
    allow(migrator).to receive(:migrate!)

    allow(Signal).to receive(:trap)
  end

  after do
    RubynCode::Tools::Registry.instance_variable_get(:@tools)&.delete_if { |k, _| k.start_with?('mcp_') }
  end

  describe 'setup_mcp_servers!' do
    context 'when no mcp.json exists' do
      before do
        allow(RubynCode::MCP::Config).to receive(:load).and_return([])
      end

      it 'initializes @mcp_clients as empty array' do
        runner = described_class.new(options)
        runner.send(:bootstrap!)

        expect(runner.instance_variable_get(:@mcp_clients)).to eq([])
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

      it 'creates and connects MCP clients during bootstrap' do
        runner = described_class.new(options)
        runner.send(:bootstrap!)

        expect(RubynCode::MCP::Client).to have_received(:from_config).with(server_configs.first)
        expect(mcp_client).to have_received(:connect!)
      end

      it 'bridges discovered tools' do
        runner = described_class.new(options)
        runner.send(:bootstrap!)

        expect(RubynCode::MCP::ToolBridge).to have_received(:bridge).with(mcp_client)
      end

      it 'stores connected clients' do
        runner = described_class.new(options)
        runner.send(:bootstrap!)

        expect(runner.instance_variable_get(:@mcp_clients)).to eq([mcp_client])
      end

      it 'displays connection info in the banner area' do
        runner = described_class.new(options)
        runner.send(:bootstrap!)

        expect(renderer).to have_received(:info).with(/MCP server 'github' connected/)
      end
    end

    context 'when a server fails to connect' do
      let(:server_configs) do
        [{ name: 'broken', command: 'nonexistent', args: [], env: {} }]
      end

      before do
        allow(RubynCode::MCP::Config).to receive(:load).and_return(server_configs)

        broken_client = instance_double(RubynCode::MCP::Client, name: 'broken')
        allow(broken_client).to receive(:connect!).and_raise(
          RubynCode::MCP::Client::ClientError, 'connection refused'
        )
        allow(RubynCode::MCP::Client).to receive(:from_config).and_return(broken_client)
      end

      it 'does not crash the bootstrap process' do
        runner = described_class.new(options)

        expect { runner.send(:bootstrap!) }.not_to raise_error
      end

      it 'keeps @mcp_clients empty for failed servers' do
        runner = described_class.new(options)
        runner.send(:bootstrap!)

        expect(runner.instance_variable_get(:@mcp_clients)).to eq([])
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

    it 'disconnects all MCP clients' do
      runner = described_class.new(options)
      runner.send(:bootstrap!)
      runner.send(:disconnect_mcp_clients!)

      expect(mcp_client).to have_received(:disconnect!)
    end

    it 'clears the clients list after disconnect' do
      runner = described_class.new(options)
      runner.send(:bootstrap!)
      runner.send(:disconnect_mcp_clients!)

      expect(runner.instance_variable_get(:@mcp_clients)).to be_empty
    end

    it 'handles disconnect errors gracefully' do
      allow(mcp_client).to receive(:disconnect!).and_raise(StandardError, 'already gone')

      runner = described_class.new(options)
      runner.send(:bootstrap!)

      expect { runner.send(:disconnect_mcp_clients!) }.not_to raise_error
    end

    it 'is safe to call when @mcp_clients is nil' do
      runner = described_class.new(options)

      expect { runner.send(:disconnect_mcp_clients!) }.not_to raise_error
    end
  end

  describe '#run ensure block disconnects MCP clients' do
    let(:server_configs) do
      [{ name: 'test-server', command: 'npx', args: [], env: {} }]
    end

    before do
      allow(RubynCode::MCP::Config).to receive(:load).and_return(server_configs)
      allow(RubynCode::MCP::Client).to receive(:from_config).and_return(mcp_client)
      allow(RubynCode::MCP::ToolBridge).to receive(:bridge).and_return([])
    end

    it 'disconnects MCP clients when daemon raises an error' do
      daemon = instance_double(RubynCode::Autonomous::Daemon)
      allow(daemon).to receive(:start!).and_raise(StandardError, 'daemon crashed')
      allow(RubynCode::Autonomous::Daemon).to receive(:new).and_return(daemon)

      runner = described_class.new(options)

      expect { runner.run }.to raise_error(SystemExit)
      expect(mcp_client).to have_received(:disconnect!)
    end
  end

  private

  # Use the class directly since this describe block names a string, not a class
  def described_class
    RubynCode::CLI::DaemonRunner
  end
end
