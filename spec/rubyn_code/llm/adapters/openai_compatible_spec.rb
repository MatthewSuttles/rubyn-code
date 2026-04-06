# frozen_string_literal: true

require 'spec_helper'
require_relative 'shared_examples'

RSpec.describe RubynCode::LLM::Adapters::OpenAICompatible do
  subject(:adapter) do
    described_class.new(
      provider: 'groq',
      base_url: 'https://api.groq.com/openai/v1',
      api_key: 'gsk-test-key',
      available_models: %w[llama-3.3-70b mixtral-8x7b]
    )
  end

  it_behaves_like 'an LLM adapter'

  let(:success_body) do
    JSON.generate(
      'id' => 'chatcmpl-groq',
      'choices' => [
        {
          'index' => 0,
          'message' => { 'role' => 'assistant', 'content' => 'Hello from Groq!' },
          'finish_reason' => 'stop'
        }
      ],
      'usage' => { 'prompt_tokens' => 8, 'completion_tokens' => 4 }
    )
  end

  describe '#provider_name' do
    it 'returns the configured provider name' do
      expect(adapter.provider_name).to eq('groq')
    end
  end

  describe '#models' do
    it 'returns the configured available models' do
      expect(adapter.models).to eq(%w[llama-3.3-70b mixtral-8x7b])
    end
  end

  describe '#chat' do
    it 'sends requests to the custom base_url' do
      stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions')
        .with(headers: { 'Authorization' => 'Bearer gsk-test-key' })
        # api_url = base_url + '/chat/completions'
        .to_return(status: 200, body: success_body)

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'llama-3.3-70b',
        max_tokens: 1024
      )

      expect(response).to be_a(RubynCode::LLM::Response)
      expect(response.text).to eq('Hello from Groq!')
    end
  end

  describe 'API key resolution' do
    it 'falls back to PROVIDER_API_KEY env var' do
      original = ENV.delete('GROQ_API_KEY')
      ENV['GROQ_API_KEY'] = 'gsk-env-key'

      keyless = described_class.new(
        provider: 'groq',
        base_url: 'https://api.groq.com/openai/v1',
        available_models: %w[llama-3.3-70b]
      )

      stub_request(:post, 'https://api.groq.com/openai/v1/chat/completions')
        .with(headers: { 'Authorization' => 'Bearer gsk-env-key' })
        .to_return(status: 200, body: success_body)

      response = keyless.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'llama-3.3-70b',
        max_tokens: 1024
      )

      expect(response.text).to eq('Hello from Groq!')
    ensure
      original ? ENV['GROQ_API_KEY'] = original : ENV.delete('GROQ_API_KEY')
    end

    it 'raises AuthExpiredError when no key is available for remote providers' do
      original = ENV.delete('GROQ_API_KEY')

      keyless = described_class.new(
        provider: 'groq',
        base_url: 'https://api.groq.com/openai/v1',
        available_models: %w[llama-3.3-70b]
      )

      expect do
        keyless.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'llama-3.3-70b', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::AuthExpiredError, /GROQ_API_KEY/)
    ensure
      ENV['GROQ_API_KEY'] = original if original
    end
  end

  describe 'local provider detection' do
    it 'skips API key requirement for localhost' do
      local = described_class.new(
        provider: 'ollama',
        base_url: 'http://localhost:11434/v1',
        available_models: %w[llama3]
      )

      stub_request(:post, 'http://localhost:11434/v1/chat/completions')
        .with(headers: { 'Authorization' => 'Bearer no-key-required' })
        .to_return(status: 200, body: success_body)

      response = local.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'llama3',
        max_tokens: 1024
      )

      expect(response).to be_a(RubynCode::LLM::Response)
    end

    it 'skips API key requirement for 127.0.0.1' do
      local = described_class.new(
        provider: 'ollama',
        base_url: 'http://127.0.0.1:11434/v1',
        available_models: %w[llama3]
      )

      stub_request(:post, 'http://127.0.0.1:11434/v1/chat/completions')
        .with(headers: { 'Authorization' => 'Bearer no-key-required' })
        .to_return(status: 200, body: success_body)

      response = local.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'llama3',
        max_tokens: 1024
      )

      expect(response).to be_a(RubynCode::LLM::Response)
    end
  end
end
