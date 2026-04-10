# frozen_string_literal: true

require 'spec_helper'
require_relative 'shared_examples'

RSpec.describe RubynCode::LLM::Adapters::AnthropicCompatible do
  subject(:adapter) do
    described_class.new(
      provider: 'bedrock-proxy',
      base_url: 'https://proxy.example.com/v1',
      api_key: 'bp-test-key',
      available_models: %w[claude-sonnet-4-6 claude-haiku-4-5]
    )
  end

  it_behaves_like 'an LLM adapter'

  let(:success_body) do
    JSON.generate(
      'id' => 'msg_proxy',
      'content' => [{ 'type' => 'text', 'text' => 'Hello from proxy!' }],
      'stop_reason' => 'end_turn',
      'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
    )
  end

  describe '#provider_name' do
    it 'returns the configured provider name' do
      expect(adapter.provider_name).to eq('bedrock-proxy')
    end
  end

  describe '#models' do
    it 'returns the configured available models' do
      expect(adapter.models).to eq(%w[claude-sonnet-4-6 claude-haiku-4-5])
    end
  end

  describe '#chat' do
    it 'sends requests to the custom base_url /messages endpoint' do
      stub_request(:post, 'https://proxy.example.com/v1/messages')
        .with(headers: { 'x-api-key' => 'bp-test-key', 'anthropic-version' => '2023-06-01' })
        .to_return(status: 200, body: success_body)

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'claude-sonnet-4-6',
        max_tokens: 1024
      )

      expect(response).to be_a(RubynCode::LLM::Response)
      expect(response.text).to eq('Hello from proxy!')
    end

    it 'does not use OAuth headers' do
      stub_request(:post, 'https://proxy.example.com/v1/messages')
        .with { |req| !req.headers.key?('Authorization') && req.headers['X-Api-Key'] == 'bp-test-key' }
        .to_return(status: 200, body: success_body)

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'claude-sonnet-4-6',
        max_tokens: 1024
      )

      expect(response.text).to eq('Hello from proxy!')
    end

    it 'parses tool_use blocks from the response' do
      tool_body = JSON.generate(
        'id' => 'msg_tool',
        'stop_reason' => 'tool_use',
        'content' => [
          { 'type' => 'text', 'text' => 'Reading...' },
          { 'type' => 'tool_use', 'id' => 'toolu_1', 'name' => 'read_file', 'input' => { 'path' => 'foo.rb' } }
        ],
        'usage' => { 'input_tokens' => 10, 'output_tokens' => 15 }
      )

      stub_request(:post, 'https://proxy.example.com/v1/messages')
        .to_return(status: 200, body: tool_body)

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Read foo.rb' }],
        model: 'claude-sonnet-4-6',
        max_tokens: 1024
      )

      expect(response.tool_use?).to be true
      tool = response.tool_calls.first
      expect(tool.name).to eq('read_file')
      expect(tool.input).to eq({ 'path' => 'foo.rb' })
    end

    it 'raises RequestError on server error' do
      stub_request(:post, 'https://proxy.example.com/v1/messages')
        .to_return(status: 500, body: '{"error":{"type":"server_error","message":"boom"}}')

      expect do
        adapter.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'test', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::RequestError, /boom/)
    end

    it 'raises AuthExpiredError on 401' do
      stub_request(:post, 'https://proxy.example.com/v1/messages')
        .to_return(status: 401, body: '{"error":{"type":"auth","message":"expired"}}')

      expect do
        adapter.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'test', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::AuthExpiredError)
    end

    it 'retries on 429 rate limit' do
      stub_request(:post, 'https://proxy.example.com/v1/messages')
        .to_return(status: 429, body: '{"error":{"type":"rate_limit","message":"slow down"}}')
        .then.to_return(status: 200, body: success_body)

      allow(adapter).to receive(:sleep)

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'claude-sonnet-4-6',
        max_tokens: 1024
      )

      expect(response.text).to eq('Hello from proxy!')
    end
  end

  describe 'API key resolution' do
    before do
      allow(RubynCode::Auth::TokenStore).to receive(:load_provider_key).and_return(nil)
    end

    it 'uses stored key from TokenStore' do
      allow(RubynCode::Auth::TokenStore).to receive(:load_provider_key)
        .with('bedrock-proxy').and_return('bp-stored-key')

      keyless = described_class.new(
        provider: 'bedrock-proxy',
        base_url: 'https://proxy.example.com/v1',
        available_models: %w[claude-sonnet-4-6]
      )

      stub_request(:post, 'https://proxy.example.com/v1/messages')
        .with(headers: { 'x-api-key' => 'bp-stored-key' })
        .to_return(status: 200, body: success_body)

      response = keyless.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'claude-sonnet-4-6',
        max_tokens: 1024
      )

      expect(response.text).to eq('Hello from proxy!')
    end

    it 'falls back to PROVIDER_API_KEY env var' do
      original = ENV.delete('BEDROCK_PROXY_API_KEY')
      ENV['BEDROCK_PROXY_API_KEY'] = 'bp-env-key'

      keyless = described_class.new(
        provider: 'bedrock-proxy',
        base_url: 'https://proxy.example.com/v1',
        available_models: %w[claude-sonnet-4-6]
      )

      stub_request(:post, 'https://proxy.example.com/v1/messages')
        .with(headers: { 'x-api-key' => 'bp-env-key' })
        .to_return(status: 200, body: success_body)

      response = keyless.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'claude-sonnet-4-6',
        max_tokens: 1024
      )

      expect(response.text).to eq('Hello from proxy!')
    ensure
      original ? ENV['BEDROCK_PROXY_API_KEY'] = original : ENV.delete('BEDROCK_PROXY_API_KEY')
    end

    it 'raises AuthExpiredError when no key is available' do
      original = ENV.delete('BEDROCK_PROXY_API_KEY')

      keyless = described_class.new(
        provider: 'bedrock-proxy',
        base_url: 'https://proxy.example.com/v1',
        available_models: %w[claude-sonnet-4-6]
      )

      expect do
        keyless.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'claude-sonnet-4-6', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::AuthExpiredError, /set-key/)
    ensure
      ENV['BEDROCK_PROXY_API_KEY'] = original if original
    end
  end
end
