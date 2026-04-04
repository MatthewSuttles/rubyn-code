# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::MCP::Client do
  let(:init_response) { { 'serverInfo' => { 'name' => 'test' }, 'capabilities' => {} } }
  let(:tools_response) { { 'tools' => [{ 'name' => 'read_file', 'description' => 'Read a file' }] } }
  let(:call_tool_response) { { 'content' => [{ 'type' => 'text', 'text' => 'result' }] } }

  let(:transport) do
    instance_double(
      'Transport',
      start!: nil,
      stop!: nil,
      alive?: true,
      send_notification: nil
    )
  end

  before do
    allow(transport).to receive(:send_request).with('initialize', anything).and_return(init_response)
    allow(transport).to receive(:send_request).with('tools/list').and_return(tools_response)
    allow(transport).to receive(:send_request).with('tools/call', anything).and_return(call_tool_response)
    allow(transport).to receive(:respond_to?).with(:send_notification).and_return(true)
  end

  subject(:client) { described_class.new(name: 'test-server', transport: transport) }

  describe '#initialize' do
    it 'sets name and transport' do
      expect(client.name).to eq('test-server')
      expect(client.transport).to eq(transport)
    end

    it 'starts uninitialized' do
      expect(client).not_to be_connected
    end
  end

  describe '#connect!' do
    it 'calls transport.start! then sets initialized' do
      client.connect!

      expect(transport).to have_received(:start!).ordered
      expect(transport).to have_received(:send_request).with('initialize', anything).ordered
      expect(client).to be_connected
    end

    it 'sends MCP initialize request with protocol version, capabilities, and client info' do
      client.connect!

      expect(transport).to have_received(:send_request).with('initialize', {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {} },
        clientInfo: {
          name: 'rubyn-code',
          version: RubynCode::VERSION
        }
      })
    end

    it 'sends notifications/initialized notification after init' do
      client.connect!

      expect(transport).to have_received(:send_notification).with('notifications/initialized')
    end

    it 'does not send notification when transport does not support it' do
      allow(transport).to receive(:respond_to?).with(:send_notification).and_return(false)

      client.connect!

      expect(transport).not_to have_received(:send_notification)
    end

    context 'when transport.start! fails' do
      before do
        allow(transport).to receive(:start!).and_raise(StandardError, 'connection refused')
      end

      it 'stops transport and raises ClientError' do
        expect { client.connect! }.to raise_error(
          described_class::ClientError,
          "Failed to connect to MCP server 'test-server': connection refused"
        )
        expect(transport).to have_received(:stop!)
      end
    end

    context 'when initialize request fails' do
      before do
        allow(transport).to receive(:send_request).with('initialize', anything)
          .and_raise(StandardError, 'protocol error')
      end

      it 'stops transport and raises ClientError wrapping original error' do
        expect { client.connect! }.to raise_error(
          described_class::ClientError,
          "Failed to connect to MCP server 'test-server': protocol error"
        )
        expect(transport).to have_received(:stop!)
        expect(client).not_to be_connected
      end
    end
  end

  describe '#tools' do
    context 'when connected' do
      before { client.connect! }

      it 'calls tools/list on transport and returns tools array' do
        result = client.tools

        expect(transport).to have_received(:send_request).with('tools/list')
        expect(result).to eq([{ 'name' => 'read_file', 'description' => 'Read a file' }])
      end

      it 'caches result on subsequent calls' do
        client.tools
        client.tools

        expect(transport).to have_received(:send_request).with('tools/list').once
      end
    end

    context 'when not connected' do
      it 'raises ClientError' do
        expect { client.tools }.to raise_error(
          described_class::ClientError,
          "Client 'test-server' is not connected. Call #connect! first."
        )
      end
    end
  end

  describe '#call_tool' do
    context 'when connected' do
      before { client.connect! }

      it 'sends tools/call request with tool name and arguments' do
        result = client.call_tool('read_file', { path: '/tmp/test.rb' })

        expect(transport).to have_received(:send_request).with('tools/call', {
          name: 'read_file',
          arguments: { path: '/tmp/test.rb' }
        })
        expect(result).to eq(call_tool_response)
      end

      it 'passes empty hash arguments by default' do
        client.call_tool('read_file')

        expect(transport).to have_received(:send_request).with('tools/call', {
          name: 'read_file',
          arguments: {}
        })
      end
    end

    context 'when not connected' do
      it 'raises ClientError' do
        expect { client.call_tool('read_file') }.to raise_error(
          described_class::ClientError,
          "Client 'test-server' is not connected. Call #connect! first."
        )
      end
    end
  end

  describe '#disconnect!' do
    before { client.connect! }

    it 'calls transport.stop!' do
      client.disconnect!

      expect(transport).to have_received(:stop!)
    end

    it 'resets initialized to false' do
      client.disconnect!

      expect(client).not_to be_connected
    end

    it 'clears tools cache' do
      client.tools
      client.disconnect!
      client.connect!

      client.tools

      # tools/list should be called twice: once before disconnect, once after reconnect
      expect(transport).to have_received(:send_request).with('tools/list').twice
    end
  end

  describe '#connected?' do
    it 'returns true when initialized and transport alive' do
      client.connect!
      allow(transport).to receive(:alive?).and_return(true)

      expect(client).to be_connected
    end

    it 'returns false when not initialized' do
      expect(client).not_to be_connected
    end

    it 'returns false when transport not alive' do
      client.connect!
      allow(transport).to receive(:alive?).and_return(false)

      expect(client).not_to be_connected
    end
  end

  describe '.from_config' do
    context 'when config has no :url key' do
      let(:config) do
        {
          name: 'stdio-server',
          command: 'node',
          args: ['server.js'],
          env: { 'DEBUG' => '1' }
        }
      end

      it 'creates a client with StdioTransport' do
        client = described_class.from_config(config)

        expect(client.name).to eq('stdio-server')
        expect(client.transport).to be_a(RubynCode::MCP::StdioTransport)
      end

      it 'passes args and env to StdioTransport' do
        stdio_transport = instance_double('StdioTransport')
        allow(RubynCode::MCP::StdioTransport).to receive(:new).and_return(stdio_transport)

        described_class.from_config(config)

        expect(RubynCode::MCP::StdioTransport).to have_received(:new).with(
          command: 'node',
          args: ['server.js'],
          env: { 'DEBUG' => '1' },
          timeout: RubynCode::MCP::StdioTransport::DEFAULT_TIMEOUT
        )
      end

      it 'uses default timeout when not specified' do
        stdio_transport = instance_double('StdioTransport')
        allow(RubynCode::MCP::StdioTransport).to receive(:new).and_return(stdio_transport)

        described_class.from_config(config)

        expect(RubynCode::MCP::StdioTransport).to have_received(:new).with(
          hash_including(timeout: RubynCode::MCP::StdioTransport::DEFAULT_TIMEOUT)
        )
      end

      it 'uses custom timeout when specified' do
        stdio_transport = instance_double('StdioTransport')
        allow(RubynCode::MCP::StdioTransport).to receive(:new).and_return(stdio_transport)

        described_class.from_config(config.merge(timeout: 60))

        expect(RubynCode::MCP::StdioTransport).to have_received(:new).with(
          hash_including(timeout: 60)
        )
      end

      it 'defaults args to empty array when not specified' do
        stdio_transport = instance_double('StdioTransport')
        allow(RubynCode::MCP::StdioTransport).to receive(:new).and_return(stdio_transport)

        described_class.from_config({ name: 'minimal', command: 'server' })

        expect(RubynCode::MCP::StdioTransport).to have_received(:new).with(
          hash_including(args: [], env: {})
        )
      end
    end

    context 'when config has :url key' do
      let(:config) do
        {
          name: 'sse-server',
          url: 'http://localhost:3000/sse'
        }
      end

      it 'creates a client with SSETransport' do
        client = described_class.from_config(config)

        expect(client.name).to eq('sse-server')
        expect(client.transport).to be_a(RubynCode::MCP::SSETransport)
      end

      it 'uses default timeout when not specified' do
        sse_transport = instance_double('SSETransport')
        allow(RubynCode::MCP::SSETransport).to receive(:new).and_return(sse_transport)

        described_class.from_config(config)

        expect(RubynCode::MCP::SSETransport).to have_received(:new).with(
          url: 'http://localhost:3000/sse',
          timeout: RubynCode::MCP::SSETransport::DEFAULT_TIMEOUT
        )
      end

      it 'uses custom timeout when specified' do
        sse_transport = instance_double('SSETransport')
        allow(RubynCode::MCP::SSETransport).to receive(:new).and_return(sse_transport)

        described_class.from_config(config.merge(timeout: 45))

        expect(RubynCode::MCP::SSETransport).to have_received(:new).with(
          url: 'http://localhost:3000/sse',
          timeout: 45
        )
      end
    end
  end
end
