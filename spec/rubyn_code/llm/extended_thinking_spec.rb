# frozen_string_literal: true

require 'spec_helper'
require 'rubyn_code/llm/message_builder'
require 'rubyn_code/llm/adapters/anthropic_streaming'

RSpec.describe 'Extended thinking plumbing' do
  describe RubynCode::LLM::ThinkingBlock do
    it 'reports type "thinking"' do
      expect(described_class.new(text: 'reasoning').type).to eq('thinking')
    end

    it 'is a Data object' do
      expect(described_class.new(text: 'a')).to be_frozen
    end
  end

  describe RubynCode::LLM::MessageBuilder do
    let(:builder) { described_class.new }

    it 'maps ThinkingBlock to Anthropic-style thinking content block' do
      msg = builder.format_messages(
        [{ role: 'assistant', content: [RubynCode::LLM::ThinkingBlock.new(text: 'I should think about this')] }]
      )
      expect(msg.first[:content].first).to eq(type: 'thinking', text: 'I should think about this')
    end
  end

  describe RubynCode::LLM::Adapters::Anthropic do
    let(:adapter) { described_class.new }

    it 'forwards thinking deltas separately from response text' do
      received = []
      streamer = adapter.send(:build_streamer, ->(*args) { received << args })
      streamer.feed <<~SSE
        event: content_block_start
        data: {"index":0,"content_block":{"type":"thinking","thinking":""}}

      SSE
      streamer.feed <<~SSE
        event: content_block_delta
        data: {"index":0,"delta":{"type":"thinking_delta","thinking":"inspect dependencies"}}

      SSE

      expect(received).to include(['inspect dependencies', :thinking])
    end

    describe '#ensure_max_tokens_for_thinking' do
      it 'returns max_tokens untouched when thinking is nil' do
        expect(adapter.send(:ensure_max_tokens_for_thinking, 8000, nil)).to eq(8000)
      end

      it 'returns max_tokens untouched when budget is zero' do
        expect(adapter.send(:ensure_max_tokens_for_thinking, 8000, { budget_tokens: 0 })).to eq(8000)
      end

      it 'raises max_tokens to budget + 1024 when too small' do
        expect(adapter.send(:ensure_max_tokens_for_thinking, 4096, { budget_tokens: 8192 })).to eq(9216)
      end

      it 'leaves max_tokens alone when already sufficient' do
        expect(adapter.send(:ensure_max_tokens_for_thinking, 16_000, { budget_tokens: 8192 })).to eq(16_000)
      end
    end

    describe '#apply_thinking' do
      it 'sets adaptive thinking on Claude 4.6+ models' do
        body = { model: 'claude-opus-4-8' }
        adapter.send(:apply_thinking, body, { budget_tokens: 1024 })
        expect(body[:thinking]).to eq(type: 'adaptive')
      end

      it 'sets enabled + budget_tokens on legacy models' do
        body = { model: 'claude-haiku-4-5' }
        adapter.send(:apply_thinking, body, { budget_tokens: 1024 })
        expect(body[:thinking]).to eq(type: 'enabled', budget_tokens: 1024)
      end

      it 'leaves body untouched when budget_tokens is zero' do
        body = { model: 'm' }
        adapter.send(:apply_thinking, body, { budget_tokens: 0 })
        expect(body).to eq(model: 'm')
      end

      it 'leaves body untouched when thinking is not a Hash' do
        body = { model: 'm' }
        adapter.send(:apply_thinking, body, nil)
        expect(body).to eq(model: 'm')
      end
    end

    describe '#parse_content_blocks' do
      it 'parses thinking blocks' do
        blocks = [{ 'type' => 'thinking', 'thinking' => 'pondering...' }]
        result = adapter.send(:parse_content_blocks, blocks)
        expect(result.first).to be_a(RubynCode::LLM::ThinkingBlock)
        expect(result.first.text).to eq('pondering...')
      end

      it 'parses text and tool_use blocks alongside thinking' do
        blocks = [
          { 'type' => 'thinking', 'thinking' => 'hmm' },
          { 'type' => 'text', 'text' => 'OK' },
          { 'type' => 'tool_use', 'id' => 't1', 'name' => 'bash', 'input' => {} }
        ]
        types = adapter.send(:parse_content_blocks, blocks).map(&:type)
        expect(types).to eq(%w[thinking text tool_use])
      end
    end
  end

  describe RubynCode::LLM::Adapters::AnthropicStreaming do
    let(:events) { [] }
    let(:streamer) { RubynCode::LLM::Adapters::AnthropicStreaming.new { |e| events << e } }

    it 'parses a thinking content block with deltas' do
      streamer.feed <<~SSE
        event: message_start
        data: {"message":{"id":"msg_1"}}

      SSE
      streamer.feed <<~SSE
        event: content_block_start
        data: {"index":0,"content_block":{"type":"thinking","thinking":""}}

      SSE
      streamer.feed <<~SSE
        event: content_block_delta
        data: {"index":0,"delta":{"type":"thinking_delta","thinking":"step 1"}}

      SSE
      streamer.feed <<~SSE
        event: content_block_stop
        data: {"index":0}

      SSE
      response = streamer.finalize
      expect(response.content.first).to be_a(RubynCode::LLM::ThinkingBlock)
      expect(response.content.first.text).to eq('step 1')
      expect(events.map(&:type)).to include(:thinking_delta)
    end
  end

  describe RubynCode::LLM::Client do
    let(:fake_adapter) do
      instance_double(RubynCode::LLM::Adapters::Anthropic).tap do |a|
        empty = RubynCode::LLM::Response.new(
          id: 'r', content: [], stop_reason: 'end_turn',
          usage: RubynCode::LLM::Usage.new(input_tokens: 0, output_tokens: 0)
        )
        allow(a).to receive(:chat) { empty }
        allow(a).to receive(:provider_name).and_return('anthropic')
        allow(a).to receive(:models).and_return(['claude-opus-4-8'])
      end
    end

    it 'starts with thinking_budget_tokens at 0' do
      client = described_class.new(adapter: fake_adapter)
      expect(client.thinking_budget_tokens).to eq(0)
    end

    it 'forwards thinking hash to adapter when budget is set' do
      client = described_class.new(adapter: fake_adapter)
      client.thinking_budget_tokens = 4096
      client.chat(messages: [{ role: 'user', content: 'hi' }])
      expect(fake_adapter).to have_received(:chat).with(hash_including(thinking: { budget_tokens: 4096 }))
    end

    it 'omits thinking when budget is 0' do
      client = described_class.new(adapter: fake_adapter)
      client.chat(messages: [{ role: 'user', content: 'hi' }])
      expect(fake_adapter).to have_received(:chat) { |kwargs| expect(kwargs).not_to have_key(:thinking) }
    end
  end
end
