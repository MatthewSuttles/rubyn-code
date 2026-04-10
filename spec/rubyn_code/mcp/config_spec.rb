# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'tmpdir'

RSpec.describe RubynCode::MCP::Config do
  let(:project_dir) { Dir.mktmpdir }
  let(:config_dir)  { File.join(project_dir, '.rubyn-code') }
  let(:config_path) { File.join(config_dir, 'mcp.json') }

  before { FileUtils.mkdir_p(config_dir) }
  after  { FileUtils.rm_rf(project_dir) }

  describe '.load' do
    context 'when no config file exists' do
      it 'returns an empty array' do
        expect(described_class.load(project_dir)).to eq([])
      end
    end

    context 'with a stdio server' do
      before do
        File.write(config_path, JSON.generate(
                                  'mcpServers' => {
                                    'test-server' => {
                                      'command' => 'npx',
                                      'args' => ['-y', '@example/server'],
                                      'env' => { 'TOKEN' => 'abc123' }
                                    }
                                  }
                                ))
      end

      it 'parses the server name' do
        servers = described_class.load(project_dir)
        expect(servers.size).to eq(1)
        expect(servers.first[:name]).to eq('test-server')
      end

      it 'parses command and args' do
        server = described_class.load(project_dir).first
        expect(server[:command]).to eq('npx')
        expect(server[:args]).to eq(['-y', '@example/server'])
      end

      it 'parses env vars' do
        server = described_class.load(project_dir).first
        expect(server[:env]).to eq({ 'TOKEN' => 'abc123' })
      end
    end

    context 'with an SSE server' do
      before do
        File.write(config_path, JSON.generate(
                                  'mcpServers' => {
                                    'remote' => {
                                      'url' => 'https://mcp.example.com/sse',
                                      'timeout' => 30
                                    }
                                  }
                                ))
      end

      it 'includes the url key' do
        server = described_class.load(project_dir).first
        expect(server[:url]).to eq('https://mcp.example.com/sse')
      end

      it 'includes the timeout key' do
        server = described_class.load(project_dir).first
        expect(server[:timeout]).to eq(30)
      end

      it 'sets command to nil for SSE servers' do
        server = described_class.load(project_dir).first
        expect(server[:command]).to be_nil
      end
    end

    context 'with environment variable expansion' do
      around do |example|
        original = ENV.fetch('MCP_TEST_TOKEN', nil)
        ENV['MCP_TEST_TOKEN'] = 'expanded-value'
        example.run
      ensure
        original ? ENV['MCP_TEST_TOKEN'] = original : ENV.delete('MCP_TEST_TOKEN')
      end

      before do
        File.write(config_path, JSON.generate(
                                  'mcpServers' => {
                                    'env-server' => {
                                      'command' => 'node',
                                      'args' => ['server.js'],
                                      'env' => { 'API_TOKEN' => '${MCP_TEST_TOKEN}' }
                                    }
                                  }
                                ))
      end

      it 'expands ${VAR} references to actual env values' do
        server = described_class.load(project_dir).first
        expect(server[:env]['API_TOKEN']).to eq('expanded-value')
      end
    end

    context 'with missing environment variable' do
      before do
        ENV.delete('DOES_NOT_EXIST_EVER_XYZ')
        File.write(config_path, JSON.generate(
                                  'mcpServers' => {
                                    'missing-env' => {
                                      'command' => 'node',
                                      'env' => { 'KEY' => '${DOES_NOT_EXIST_EVER_XYZ}' }
                                    }
                                  }
                                ))
      end

      it 'replaces with empty string and warns' do
        server = described_class.load(project_dir).first
        expect(server[:env]['KEY']).to eq('')
      end
    end

    context 'with invalid JSON' do
      before { File.write(config_path, 'not json{{{') }

      it 'returns an empty array' do
        expect(described_class.load(project_dir)).to eq([])
      end
    end

    context 'with multiple servers' do
      before do
        File.write(config_path, JSON.generate(
                                  'mcpServers' => {
                                    'alpha' => { 'command' => 'cmd-a', 'args' => [] },
                                    'beta' => { 'url' => 'https://beta.example.com' }
                                  }
                                ))
      end

      it 'parses all servers' do
        servers = described_class.load(project_dir)
        expect(servers.map { |s| s[:name] }).to contain_exactly('alpha', 'beta')
      end

      it 'distinguishes stdio from SSE servers' do
        servers = described_class.load(project_dir)
        stdio = servers.find { |s| s[:name] == 'alpha' }
        sse   = servers.find { |s| s[:name] == 'beta' }

        expect(stdio[:command]).to eq('cmd-a')
        expect(stdio[:url]).to be_nil

        expect(sse[:url]).to eq('https://beta.example.com')
        expect(sse[:command]).to be_nil
      end
    end
  end
end
