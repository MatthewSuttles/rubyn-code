# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::CLI::Commands::Mcp do
  subject(:command) { described_class.new }

  let(:renderer) { instance_double(RubynCode::CLI::Renderer, info: nil) }
  let(:project_root) { '/tmp/test-project' }
  let(:ctx) do
    instance_double(
      RubynCode::CLI::Commands::Context,
      renderer: renderer,
      project_root: project_root
    )
  end

  describe '.command_name' do
    it { expect(described_class.command_name).to eq('/mcp') }
  end

  describe '.description' do
    it { expect(described_class.description).to eq('MCP server status') }
  end

  describe '#execute' do
    context 'when no servers are configured' do
      before do
        allow(RubynCode::MCP::Config).to receive(:load).with(project_root).and_return([])
      end

      it 'shows a helpful message' do
        expect { command.execute([], ctx) }.to output(/mcp\.json/).to_stdout
        expect(renderer).to have_received(:info).with('No MCP servers configured.')
      end
    end

    context 'when servers are configured' do
      let(:server_configs) do
        [
          { name: 'test-server', command: 'node', args: ['server.js'], env: {} }
        ]
      end

      let(:mock_client) do
        instance_double(RubynCode::MCP::Client, connected?: true, tools: [{ 'name' => 'tool1' }])
      end

      before do
        allow(RubynCode::MCP::Config).to receive(:load).with(project_root).and_return(server_configs)
        allow(RubynCode::MCP::Client).to receive(:from_config).and_return(mock_client)
        allow(mock_client).to receive(:connect!)
        allow(mock_client).to receive(:disconnect!)
      end

      it 'displays server count' do
        expect { command.execute([], ctx) }.to output(/test-server/).to_stdout
        expect(renderer).to have_received(:info).with('MCP servers (1):')
      end

      it 'shows connected status and tool count' do
        expect { command.execute([], ctx) }.to output(/connected.*1 tools/).to_stdout
      end

      it 'shows transport info' do
        expect { command.execute([], ctx) }.to output(/stdio.*node server\.js/).to_stdout
      end

      it 'disconnects after probing' do
        command.execute([], ctx)
        expect(mock_client).to have_received(:disconnect!)
      end
    end

    context 'when a server fails to connect' do
      let(:server_configs) do
        [
          { name: 'broken-server', command: 'missing-cmd', args: [], env: {} }
        ]
      end

      let(:mock_client) do
        instance_double(RubynCode::MCP::Client, connected?: false)
      end

      before do
        allow(RubynCode::MCP::Config).to receive(:load).with(project_root).and_return(server_configs)
        allow(RubynCode::MCP::Client).to receive(:from_config).and_return(mock_client)
        allow(mock_client).to receive(:connect!).and_raise(
          RubynCode::MCP::Client::ClientError, 'connection refused'
        )
        allow(mock_client).to receive(:disconnect!)
      end

      it 'shows error status' do
        expect { command.execute([], ctx) }.to output(/broken-server \[error\]/).to_stdout
      end
    end

    context 'with an SSE server' do
      let(:server_configs) do
        [
          { name: 'remote', url: 'https://mcp.example.com/sse' }
        ]
      end

      let(:mock_client) do
        instance_double(RubynCode::MCP::Client, connected?: true, tools: [])
      end

      before do
        allow(RubynCode::MCP::Config).to receive(:load).with(project_root).and_return(server_configs)
        allow(RubynCode::MCP::Client).to receive(:from_config).and_return(mock_client)
        allow(mock_client).to receive(:connect!)
        allow(mock_client).to receive(:disconnect!)
      end

      it 'shows SSE transport info' do
        expect { command.execute([], ctx) }.to output(/SSE.*mcp\.example\.com/).to_stdout
      end
    end
  end
end
