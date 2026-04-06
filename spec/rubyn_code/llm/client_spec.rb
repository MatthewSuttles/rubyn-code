# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::LLM::Client do
  subject(:client) { described_class.new(model: 'claude-sonnet-4-20250514') }

  before do
    allow(RubynCode::Auth::TokenStore).to receive(:valid?).and_return(true)
    allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(
      {
        access_token: 'sk-ant-oat-test-token',
        expires_at: Time.now + 3600,
        source: :keychain
      }
    )
  end

  describe '#initialize' do
    it 'defaults to anthropic provider' do
      expect(client.provider_name).to eq('anthropic')
    end

    it 'defaults to the configured model' do
      expect(client.model).to eq('claude-sonnet-4-20250514')
    end

    it 'accepts a custom adapter' do
      adapter = instance_double(RubynCode::LLM::Adapters::Base, provider_name: 'test')
      custom_client = described_class.new(adapter: adapter)
      expect(custom_client.provider_name).to eq('test')
    end

    it 'resolves openai provider' do
      openai_client = described_class.new(provider: 'openai')
      expect(openai_client.provider_name).to eq('openai')
      expect(openai_client.adapter).to be_a(RubynCode::LLM::Adapters::OpenAI)
    end

    it 'resolves providers configured in config.yml' do
      settings = instance_double(
        RubynCode::Config::Settings,
        provider_config: { 'base_url' => 'https://api.groq.com/openai/v1' }
      )
      allow(RubynCode::Config::Settings).to receive(:new).and_return(settings)

      groq_client = described_class.new(provider: 'groq')
      expect(groq_client.provider_name).to eq('groq')
      expect(groq_client.adapter).to be_a(RubynCode::LLM::Adapters::OpenAICompatible)
    end

    it 'raises ConfigError when provider has no config' do
      settings = instance_double(RubynCode::Config::Settings, provider_config: nil)
      allow(RubynCode::Config::Settings).to receive(:new).and_return(settings)

      expect { described_class.new(provider: 'martian-ai') }
        .to raise_error(RubynCode::ConfigError, /Unknown provider/)
    end

    it 'raises ConfigError when provider config has no base_url' do
      settings = instance_double(
        RubynCode::Config::Settings,
        provider_config: { 'models' => ['some-model'] }
      )
      allow(RubynCode::Config::Settings).to receive(:new).and_return(settings)

      expect { described_class.new(provider: 'incomplete') }
        .to raise_error(RubynCode::ConfigError, /Unknown provider/)
    end
  end

  describe '#model=' do
    it 'allows changing the model at runtime' do
      client.model = 'claude-opus-4-20250514'
      expect(client.model).to eq('claude-opus-4-20250514')
    end
  end

  describe '#switch_provider!' do
    it 'swaps to OpenAI adapter' do
      client.switch_provider!('openai', model: 'gpt-4o')
      expect(client.provider_name).to eq('openai')
      expect(client.model).to eq('gpt-4o')
      expect(client.adapter).to be_a(RubynCode::LLM::Adapters::OpenAI)
    end

    it 'swaps back to Anthropic' do
      client.switch_provider!('openai')
      client.switch_provider!('anthropic', model: 'claude-sonnet-4-20250514')
      expect(client.provider_name).to eq('anthropic')
      expect(client.adapter).to be_a(RubynCode::LLM::Adapters::Anthropic)
    end

    it 'keeps existing model when no model given' do
      client.switch_provider!('openai')
      expect(client.model).to eq('claude-sonnet-4-20250514')
    end
  end

  describe '#models' do
    it 'returns anthropic models by default' do
      expect(client.models).to include('claude-sonnet-4-20250514')
    end

    it 'returns openai models after provider switch' do
      client.switch_provider!('openai')
      expect(client.models).to include('gpt-4o')
    end
  end

  describe '#chat' do
    it 'sends a proper OAuth request and parses the response' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with(
          headers: {
            'Authorization' => 'Bearer sk-ant-oat-test-token',
            'anthropic-version' => '2023-06-01',
            'anthropic-beta' => 'oauth-2025-04-20',
            'x-app' => 'cli'
          }
        )
        .to_return(
          status: 200,
          body: JSON.generate({
                                'id' => 'msg_test',
                                'content' => [{ 'type' => 'text', 'text' => 'Hello!' }],
                                'stop_reason' => 'end_turn',
                                'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
                              }),
          headers: { 'Content-Type' => 'application/json' }
        )

      response = client.chat(messages: [{ role: 'user', content: 'Hi' }])

      expect(response).to be_a(RubynCode::LLM::Response)
      expect(response.text).to eq('Hello!')
      expect(response.usage.input_tokens).to eq(10)
    end

    it 'includes the OAuth gate in the system prompt' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with do |req|
          body = JSON.parse(req.body)
          system_blocks = body['system']
          system_blocks.is_a?(Array) &&
            system_blocks.first['text'].include?('Claude Code') &&
            system_blocks.last['cache_control'] == { 'type' => 'ephemeral' }
        end
        .to_return(
          status: 200,
          body: JSON.generate({
                                'id' => 'msg_test',
                                'content' => [{ 'type' => 'text', 'text' => 'OK' }],
                                'stop_reason' => 'end_turn',
                                'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
                              })
        )

      client.chat(messages: [{ role: 'user', content: 'Hi' }], system: 'Be helpful.')
    end

    it 'raises RequestError on non-success status' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 500, body: '{"error":{"type":"server_error","message":"boom"}}')

      expect { client.chat(messages: [{ role: 'user', content: 'Hi' }]) }
        .to raise_error(RubynCode::LLM::Client::RequestError, /boom/)
    end

    it 'raises AuthExpiredError on 401' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 401, body: '{"error":{"type":"auth","message":"expired"}}')

      expect { client.chat(messages: [{ role: 'user', content: 'Hi' }]) }
        .to raise_error(RubynCode::LLM::Client::AuthExpiredError)
    end

    it 'raises PromptTooLongError on 413' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 413, body: '{"error":{"type":"invalid_request_error","message":"prompt is too long"}}')

      expect { client.chat(messages: [{ role: 'user', content: 'Hi' }]) }
        .to raise_error(RubynCode::LLM::Client::PromptTooLongError)
    end

    it 'retries on 429 rate limit' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(status: 429, body: '{"error":{"type":"rate_limit","message":"slow down"}}')
        .then.to_return(
          status: 200,
          body: JSON.generate({
                                'id' => 'msg_retry', 'content' => [{ 'type' => 'text', 'text' => 'Retried!' }],
                                'stop_reason' => 'end_turn', 'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
                              })
        )

      allow(client).to receive(:sleep) # Don't actually sleep in tests

      response = client.chat(messages: [{ role: 'user', content: 'Hi' }])
      expect(response.text).to eq('Retried!')
    end

    it 'calls on_text callback with text content for non-streaming (API key auth)' do
      allow(RubynCode::Auth::TokenStore).to receive(:load).and_return(
        {
          access_token: 'sk-ant-api01-test-key',
          expires_at: Time.now + 3600,
          source: :env
        }
      )

      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: JSON.generate({
                                'id' => 'msg_cb', 'content' => [{ 'type' => 'text', 'text' => 'Callback text' }],
                                'stop_reason' => 'end_turn', 'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
                              })
        )

      received = nil
      on_text = ->(text) { received = text }
      client.chat(messages: [{ role: 'user', content: 'Hi' }], on_text: on_text)
      expect(received).to eq('Callback text')
    end

    it 'applies cache_control to the last message block' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with do |req|
          body = JSON.parse(req.body)
          msgs = body['messages']
          last = msgs.last
          content = last['content']
          content.is_a?(Array) && content.last['cache_control'] == { 'type' => 'ephemeral' }
        end
        .to_return(
          status: 200,
          body: JSON.generate({
                                'id' => 'msg_cache', 'content' => [{ 'type' => 'text', 'text' => 'OK' }],
                                'stop_reason' => 'end_turn', 'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
                              })
        )

      client.chat(messages: [{ role: 'user', content: [{ type: 'text', text: 'Hi' }] }])
    end

    it 'includes system as cached block when provided' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .with do |req|
          body = JSON.parse(req.body)
          system = body['system']
          system.is_a?(Array) && system.any? { |b| b['cache_control'] }
        end
        .to_return(
          status: 200,
          body: JSON.generate({
                                'id' => 'msg_sys', 'content' => [{ 'type' => 'text', 'text' => 'OK' }],
                                'stop_reason' => 'end_turn', 'usage' => { 'input_tokens' => 10, 'output_tokens' => 5 }
                              })
        )

      client.chat(messages: [{ role: 'user', content: 'Hi' }], system: 'Be helpful.')
    end

    it 'parses tool_use blocks from the response' do
      stub_request(:post, 'https://api.anthropic.com/v1/messages')
        .to_return(
          status: 200,
          body: JSON.generate({
                                'id' => 'msg_tool', 'stop_reason' => 'tool_use',
                                'content' => [
                                  { 'type' => 'text', 'text' => 'Reading file...' },
                                  { 'type' => 'tool_use', 'id' => 'toolu_1', 'name' => 'read_file',
                                    'input' => { 'path' => 'foo.rb' } }
                                ],
                                'usage' => { 'input_tokens' => 10, 'output_tokens' => 15 }
                              })
        )

      response = client.chat(messages: [{ role: 'user', content: 'Read foo.rb' }])
      tool_blocks = response.content.grep(RubynCode::LLM::ToolUseBlock)
      expect(tool_blocks.size).to eq(1)
      expect(tool_blocks.first.name).to eq('read_file')
      expect(tool_blocks.first.input).to eq({ 'path' => 'foo.rb' })
    end
  end

  describe '#ensure_valid_token! with expired OAuth' do
    it 'raises AuthExpiredError when no valid auth exists' do
      allow(RubynCode::Auth::TokenStore).to receive(:valid?).and_return(false)

      expect { client.chat(messages: [{ role: 'user', content: 'Hi' }]) }
        .to raise_error(RubynCode::LLM::Client::AuthExpiredError, /No valid authentication/)
    end
  end
end
