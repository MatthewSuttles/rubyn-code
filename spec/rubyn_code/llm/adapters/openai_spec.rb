# frozen_string_literal: true

require 'spec_helper'
require_relative 'shared_examples'

RSpec.describe RubynCode::LLM::Adapters::OpenAI do
  subject(:adapter) { described_class.new(api_key: 'sk-test-key') }

  it_behaves_like 'an LLM adapter'

  let(:success_body) do
    JSON.generate(
      'id' => 'chatcmpl-test',
      'choices' => [
        {
          'index' => 0,
          'message' => { 'role' => 'assistant', 'content' => 'Hello!' },
          'finish_reason' => 'stop'
        }
      ],
      'usage' => { 'prompt_tokens' => 10, 'completion_tokens' => 5 }
    )
  end

  let(:tool_use_body) do
    JSON.generate(
      'id' => 'chatcmpl-tool',
      'choices' => [
        {
          'index' => 0,
          'message' => {
            'role' => 'assistant',
            'content' => 'Reading...',
            'tool_calls' => [
              {
                'id' => 'call_1',
                'type' => 'function',
                'function' => {
                  'name' => 'read_file',
                  'arguments' => '{"path":"foo.rb"}'
                }
              }
            ]
          },
          'finish_reason' => 'tool_calls'
        }
      ],
      'usage' => { 'prompt_tokens' => 10, 'completion_tokens' => 15 }
    )
  end

  let(:api_url) { 'https://api.openai.com/v1/chat/completions' }

  describe '#chat' do
    it 'sends a proper request and returns an LLM::Response' do
      stub_request(:post, api_url)
        .with(headers: { 'Authorization' => 'Bearer sk-test-key' })
        .to_return(status: 200, body: success_body, headers: { 'Content-Type' => 'application/json' })

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'gpt-4o',
        max_tokens: 1024
      )

      expect(response).to be_a(RubynCode::LLM::Response)
      expect(response.text).to eq('Hello!')
      expect(response.stop_reason).to eq('end_turn')
      expect(response.usage.input_tokens).to eq(10)
      expect(response.usage.output_tokens).to eq(5)
    end

    it 'builds the system prompt as a system message' do
      stub_request(:post, api_url)
        .with do |req|
          body = JSON.parse(req.body)
          messages = body['messages']
          messages.first == { 'role' => 'system', 'content' => 'Be helpful.' }
        end
        .to_return(status: 200, body: success_body)

      adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        system: 'Be helpful.',
        model: 'gpt-4o',
        max_tokens: 1024
      )
    end

    it 'formats tool schemas in OpenAI function format' do
      tools = [
        { name: 'read_file', description: 'Read a file', input_schema: { type: 'object', properties: { path: { type: 'string' } } } }
      ]

      stub_request(:post, api_url)
        .with do |req|
          body = JSON.parse(req.body)
          tool = body['tools']&.first
          tool && tool['type'] == 'function' &&
            tool.dig('function', 'name') == 'read_file' &&
            tool.dig('function', 'parameters', 'type') == 'object'
        end
        .to_return(status: 200, body: success_body)

      adapter.chat(
        messages: [{ role: 'user', content: 'Read foo.rb' }],
        tools: tools,
        model: 'gpt-4o',
        max_tokens: 1024
      )
    end

    it 'parses tool_use blocks from the response' do
      stub_request(:post, api_url)
        .to_return(status: 200, body: tool_use_body)

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Read foo.rb' }],
        model: 'gpt-4o',
        max_tokens: 1024
      )

      expect(response.tool_use?).to be true
      expect(response.stop_reason).to eq('tool_use')
      tool = response.tool_calls.first
      expect(tool.name).to eq('read_file')
      expect(tool.input).to eq({ 'path' => 'foo.rb' })
    end

    it 'retries on 429 rate limit' do
      stub_request(:post, api_url)
        .to_return(status: 429, body: '{"error":{"message":"rate limited"}}')
        .then.to_return(status: 200, body: success_body)

      allow(adapter).to receive(:sleep)

      response = adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'gpt-4o',
        max_tokens: 1024
      )

      expect(response.text).to eq('Hello!')
    end

    it 'raises RequestError on server error' do
      stub_request(:post, api_url)
        .to_return(status: 500, body: '{"error":{"message":"internal error"}}')

      expect do
        adapter.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'gpt-4o', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::RequestError, /internal error/)
    end

    it 'raises AuthExpiredError on 401' do
      stub_request(:post, api_url)
        .to_return(status: 401, body: '{"error":{"message":"invalid api key"}}')

      expect do
        adapter.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'gpt-4o', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::AuthExpiredError)
    end

    it 'raises PromptTooLongError on 413' do
      stub_request(:post, api_url)
        .to_return(status: 413, body: '{"error":{"message":"prompt too long"}}')

      expect do
        adapter.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'gpt-4o', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::PromptTooLongError)
    end

    it 'raises AuthExpiredError when no API key is available' do
      original = ENV.delete('OPENAI_API_KEY')
      keyless_adapter = described_class.new

      expect do
        keyless_adapter.chat(messages: [{ role: 'user', content: 'Hi' }], model: 'gpt-4o', max_tokens: 100)
      end.to raise_error(RubynCode::LLM::Client::AuthExpiredError, /No OpenAI API key/)
    ensure
      ENV['OPENAI_API_KEY'] = original if original
    end

    it 'calls on_text callback during streaming' do
      response = RubynCode::LLM::Response.new(
        id: 'chatcmpl-test',
        content: [RubynCode::LLM::TextBlock.new(text: 'Hello!')],
        stop_reason: 'end_turn',
        usage: RubynCode::LLM::Usage.new(input_tokens: 10, output_tokens: 5)
      )

      allow(adapter).to receive(:stream_request).and_return(response)

      received = nil
      result = adapter.chat(
        messages: [{ role: 'user', content: 'Hi' }],
        model: 'gpt-4o',
        max_tokens: 1024,
        on_text: ->(text) { received = text }
      )

      expect(result).to be_a(RubynCode::LLM::Response)
      expect(adapter).to have_received(:stream_request)
    end
  end

  describe '#provider_name' do
    it 'returns openai' do
      expect(adapter.provider_name).to eq('openai')
    end
  end

  describe '#models' do
    it 'returns available OpenAI models' do
      expect(adapter.models).to include('gpt-4o', 'gpt-4o-mini')
      expect(adapter.models).to all(be_a(String))
    end
  end
end
