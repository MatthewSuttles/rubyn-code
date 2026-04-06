# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::LLM::Adapters::OpenAIMessageTranslator do
  # Include the module in a test harness so we can call its private methods
  let(:translator) do
    Class.new do
      include RubynCode::LLM::Adapters::OpenAIMessageTranslator

      # Expose private methods for testing
      public :build_messages, :translate_message, :stringify_content
    end.new
  end

  describe '#build_messages' do
    it 'prepends a system message when system prompt is provided' do
      result = translator.build_messages(
        [{ role: 'user', content: 'Hi' }],
        'Be helpful.'
      )

      expect(result.first).to eq({ role: 'system', content: 'Be helpful.' })
      expect(result.last).to eq({ role: 'user', content: 'Hi' })
    end

    it 'omits system message when system is nil' do
      result = translator.build_messages(
        [{ role: 'user', content: 'Hi' }],
        nil
      )

      expect(result.size).to eq(1)
      expect(result.first[:role]).to eq('user')
    end

    it 'handles an empty message list' do
      result = translator.build_messages([], 'System prompt')
      expect(result).to eq([{ role: 'system', content: 'System prompt' }])
    end
  end

  describe 'tool result translation' do
    it 'converts Anthropic tool_result blocks to OpenAI tool messages' do
      messages = [
        {
          role: 'user',
          content: [
            { type: 'tool_result', tool_use_id: 'call_1', content: 'file contents here' },
            { type: 'tool_result', tool_use_id: 'call_2', content: 'another result' }
          ]
        }
      ]

      result = translator.build_messages(messages, nil)

      expect(result.size).to eq(2)
      expect(result[0]).to eq({ role: 'tool', tool_call_id: 'call_1', content: 'file contents here' })
      expect(result[1]).to eq({ role: 'tool', tool_call_id: 'call_2', content: 'another result' })
    end

    it 'handles string-keyed tool_result blocks' do
      messages = [
        {
          'role' => 'user',
          'content' => [
            { 'type' => 'tool_result', 'tool_use_id' => 'call_1', 'content' => 'result' }
          ]
        }
      ]

      result = translator.build_messages(messages, nil)

      expect(result.first).to eq({ role: 'tool', tool_call_id: 'call_1', content: 'result' })
    end
  end

  describe 'assistant tool_use translation' do
    it 'converts Anthropic tool_use blocks to OpenAI tool_calls format' do
      messages = [
        {
          role: 'assistant',
          content: [
            { type: 'text', text: 'Let me read that.' },
            { type: 'tool_use', id: 'call_1', name: 'read_file', input: { path: 'foo.rb' } }
          ]
        }
      ]

      result = translator.build_messages(messages, nil)

      expect(result.size).to eq(1)
      msg = result.first
      expect(msg[:role]).to eq('assistant')
      expect(msg[:content]).to eq('Let me read that.')
      expect(msg[:tool_calls].size).to eq(1)

      tc = msg[:tool_calls].first
      expect(tc[:id]).to eq('call_1')
      expect(tc[:type]).to eq('function')
      expect(tc[:function][:name]).to eq('read_file')
      expect(JSON.parse(tc[:function][:arguments])).to eq({ 'path' => 'foo.rb' })
    end

    it 'handles assistant messages with only tool_use blocks (no text)' do
      messages = [
        {
          role: 'assistant',
          content: [
            { type: 'tool_use', id: 'call_1', name: 'bash', input: { command: 'ls' } }
          ]
        }
      ]

      result = translator.build_messages(messages, nil)

      msg = result.first
      expect(msg[:role]).to eq('assistant')
      expect(msg).not_to have_key(:content)
      expect(msg[:tool_calls].size).to eq(1)
    end

    it 'serializes input hash to JSON arguments string' do
      messages = [
        {
          role: 'assistant',
          content: [
            { type: 'tool_use', id: 'call_1', name: 'write_file', input: { path: 'x.rb', content: 'hello' } }
          ]
        }
      ]

      result = translator.build_messages(messages, nil)

      args = result.first[:tool_calls].first[:function][:arguments]
      expect(args).to be_a(String)
      expect(JSON.parse(args)).to eq({ 'path' => 'x.rb', 'content' => 'hello' })
    end

    it 'passes through string arguments without re-encoding' do
      messages = [
        {
          role: 'assistant',
          content: [
            { type: 'tool_use', id: 'call_1', name: 'read_file', input: '{"path":"foo.rb"}' }
          ]
        }
      ]

      result = translator.build_messages(messages, nil)

      args = result.first[:tool_calls].first[:function][:arguments]
      expect(args).to eq('{"path":"foo.rb"}')
    end
  end

  describe 'plain message passthrough' do
    it 'passes through simple user messages unchanged' do
      messages = [{ role: 'user', content: 'Hello' }]

      result = translator.build_messages(messages, nil)

      expect(result).to eq([{ role: 'user', content: 'Hello' }])
    end

    it 'passes through simple assistant messages unchanged' do
      messages = [{ role: 'assistant', content: 'Hi there' }]

      result = translator.build_messages(messages, nil)

      expect(result).to eq([{ role: 'assistant', content: 'Hi there' }])
    end
  end

  describe '#stringify_content' do
    it 'returns strings as-is' do
      expect(translator.stringify_content('hello')).to eq('hello')
    end

    it 'joins text blocks from arrays' do
      blocks = [{ text: 'Hello' }, { text: ' world' }]
      expect(translator.stringify_content(blocks)).to eq('Hello world')
    end

    it 'handles string-keyed text blocks' do
      blocks = [{ 'text' => 'Hello' }]
      expect(translator.stringify_content(blocks)).to eq('Hello')
    end

    it 'falls back to to_s for non-string non-array content' do
      expect(translator.stringify_content(42)).to eq('42')
    end
  end
end
