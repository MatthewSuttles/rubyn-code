# frozen_string_literal: true

require 'spec_helper'
require_relative 'shared_examples'

RSpec.describe RubynCode::LLM::Adapters::Anthropic do
  subject(:adapter) { described_class.new }

  it_behaves_like 'an LLM adapter'

  let(:oauth_token) do
    { access_token: 'sk-ant-oat-test-token', expires_at: Time.now + 3600, source: :keychain }
  end

  let(:api_key_token) do
    { access_token: 'sk-ant-api01-test-key', expires_at: Time.now + 3600, source: :env }
  end

  let(:success_body) do
    JSON.generate(
      'id' => 'msg_test',
      'content' => [{ 'type' => 'text', 'text' => 'Hello!' }],
      'stop_reason' => 'end_turn',
      'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
    )
  end

  before do
    allow(RubynCode::Auth::TokenStore).to receive(:valid?).and_return(true)
    allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(oauth_token)
  end

  describe '#chat' do
    it 'sends a proper OAuth request and returns an LLM::Response' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(
          headers: {
            'Authorization' => 'Bearer sk-ant-oat-test-token',
            'anthropic-version' => '2023-06-01',
            'anthropic-beta' => 'oauth-2025-04-20'
          }
        )
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024
      )

      expect(response).to be_a(RubynCode::LLM::Response)
      expect(response.text).to eq('Hello!')
      expect(response.usage.input_tokens).to eq(10)
    end

    it 'uses x-api-key header for non-OAuth tokens' do
      allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(api_key_token)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(headers: { 'x-api-key' => 'sk-ant-api01-test-key' })
        .to_return(status: 200, body: success_body)

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024
      )

      expect(response.text).to eq('Hello!')
    end

    it 'includes the OAuth gate in system blocks' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with do |req|
          body = JSON.parse(req.body)
          system_blocks = body['system']
          system_blocks.is_a?(Array) &&
            system_blocks.first['text'].include?('Claude Code') &&
            system_blocks.last['text'] == 'Be helpful.'
        end
        .to_return(status: 200, body: success_body)

      adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        system: 'Be helpful.',
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024
      )
    end

    it 'applies cache_control to the last message block' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with do |req|
          body = JSON.parse(req.body)
          last_content = body['messages'].last['content']
          last_content.is_a?(Array) && last_content.last['cache_control'] == { 'type' => 'ephemeral' }
        end
        .to_return(status: 200, body: success_body)

      adapter.chat(
        messages: [{ role: 'user', content: [{ type: 'text', text: 'Hi' }] }],
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024
      )
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

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: tool_body)

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Read foo.rb' }],
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024
      )

      expect(response.tool_use?).to be true
      tool = response.tool_calls.first
      expect(tool.name).to eq('read_file')
      expect(tool.input).to eq({ 'path' => 'foo.rb' })
    end

    it 'retries on 429 rate limit' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 429, body: '{"error":{"type":"rate_limit","message":"slow down"}}')
        .then.to_return(status: 200, body: success_body)

      allow(adapter).to receive(:sleep)

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024
      )

      expect(response.text).to eq('Hello!')
    end

    it 'raises RequestError on server error' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 500, body: '{"error":{"type":"server_error","message":"boom"}}')

      expect do
        adapter.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'test', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::RequestError, /boom/)
    end

    it 'raises AuthExpiredError on 401' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 401, body: '{"error":{"type":"auth","message":"expired"}}')

      expect do
        adapter.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'test', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::AuthExpiredError)
    end

    it 'raises PromptTooLongError on 413' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 413, body: '{"error":{"type":"invalid_request_error","message":"prompt is too long"}}')

      expect do
        adapter.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'test', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::PromptTooLongError)
    end

    it 'raises AuthExpiredError when no valid auth exists' do
      allow(RubynCode::Auth::TokenStore).to receive(:valid?).and_return(false)

      expect do
        adapter.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'test', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::AuthExpiredError, /No valid authentication/)
    end

    it 'calls on_text callback for non-streaming responses' do
      allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(api_key_token)

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 200, body: success_body)

      received = nil
      adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024,
        on_text: ->(text) { received = text }
      )

      expect(received).to eq('Hello!')
    end
  end
end
