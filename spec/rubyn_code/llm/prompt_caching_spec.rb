# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::LLM::Adapters::Anthropic, 'prompt caching' do
  let(:adapter) { described_class.new }

  def build_body(**args)
    adapter.send(:build_request_body, messages: [{ role: 'user', content: 'hi' }],
                                      tools: nil,
                                      system: nil,
                                      model: 'claude-opus-4-8',
                                      max_tokens: 8000,
                                      stream: false, **args)
  end

  before do
    allow(adapter).to receive(:access_token).and_return('sk-ant-oat-test-token')
  end

  describe 'OAuth system prompt caching' do
    it 'adds cache_control to both system blocks for OAuth' do
      body = build_body(system: 'You are helpful.')

      expect(body[:system]).to be_an(Array)
      expect(body[:system].size).to eq(2)
      expect(body[:system][0][:cache_control]).to eq({ type: 'ephemeral' })
      expect(body[:system][0][:text]).to include('Claude Code')
      expect(body[:system][1][:cache_control]).to eq({ type: 'ephemeral' })
      expect(body[:system][1][:text]).to eq('You are helpful.')
    end

    it 'only includes OAuth gate when no system prompt given' do
      body = build_body(system: nil)

      expect(body[:system]).to be_an(Array)
      expect(body[:system].size).to eq(1)
      expect(body[:system][0][:text]).to include('Claude Code')
    end
  end

  describe 'tool definition caching' do
    it 'marks the last tool with cache_control' do
      tools = [
        { name: 'read_file', description: 'Read', input_schema: {} },
        { name: 'write_file', description: 'Write', input_schema: {} }
      ]
      body = build_body(tools: tools)

      expect(body[:tools].last[:cache_control]).to eq({ type: 'ephemeral' })
      expect(body[:tools].first[:cache_control]).to be_nil
    end

    it 'does not mutate the original tool definitions' do
      tools = [
        { name: 'read_file', description: 'Read', input_schema: {} }
      ]
      build_body(tools: tools)

      expect(tools.first[:cache_control]).to be_nil
    end

    it 'does not add tools when empty' do
      body = build_body(tools: [])
      expect(body[:tools]).to be_nil
    end
  end

  describe 'message cache breakpoint' do
    it 'tags the last message content with cache_control' do
      messages = [
        { role: 'user', content: 'first' },
        { role: 'assistant', content: [{ type: 'text', text: 'reply' }] }
      ]
      body = build_body(messages: messages)

      expect(body[:messages].last[:content].last[:cache_control]).to eq({ type: 'ephemeral' })
    end

    it 'wraps string content of the last message in a tagged text block' do
      body = build_body(messages: [{ role: 'user', content: 'hi' }])

      expect(body[:messages].last[:content])
        .to eq([{ type: 'text', text: 'hi', cache_control: { type: 'ephemeral' } }])
    end

    it 'does not mutate the original messages' do
      messages = [
        { role: 'user', content: 'first' },
        { role: 'assistant', content: [{ type: 'text', text: 'reply' }] }
      ]
      build_body(messages: messages)

      expect(messages[0]).to eq(role: 'user', content: 'first')
      expect(messages[1][:content]).to eq([{ type: 'text', text: 'reply' }])
    end

    it 'only copies the last message, passing earlier ones through by reference' do
      messages = [
        { role: 'user', content: 'first' },
        { role: 'assistant', content: [{ type: 'text', text: 'reply' }] },
        { role: 'user', content: 'latest' }
      ]
      body = build_body(messages: messages)

      expect(body[:messages][0]).to equal(messages[0])
      expect(body[:messages][1]).to equal(messages[1])
      expect(body[:messages][2]).not_to equal(messages[2])
    end
  end
end
