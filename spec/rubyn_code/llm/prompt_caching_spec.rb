# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::LLM::Adapters::Anthropic, 'prompt caching' do
  let(:adapter) { described_class.new }

  def build_body(**args)
    adapter.send(:build_request_body, **{
      messages: [{ role: 'user', content: 'hi' }],
      tools: nil,
      system: nil,
      model: 'claude-opus-4-6',
      max_tokens: 8000,
      stream: false
    }.merge(args))
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
end
