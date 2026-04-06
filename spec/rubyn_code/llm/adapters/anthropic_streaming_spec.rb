# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::LLM::Adapters::AnthropicStreaming do
  describe 'text streaming' do
    it 'assembles text blocks from SSE events' do
      texts = []
      streamer = described_class.new do |event|
        texts << event.data[:text] if event.type == :text_delta
      end

      streamer.feed(<<~SSE)
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":0}}}

      SSE

      streamer.feed(<<~SSE)
        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

      SSE

      streamer.feed(<<~SSE)
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}

      SSE

      streamer.feed(<<~SSE)
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" world"}}

      SSE

      streamer.feed(<<~SSE)
        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

      SSE

      streamer.feed(<<~SSE)
        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":5}}

      SSE

      streamer.feed(<<~SSE)
        event: message_stop
        data: {"type":"message_stop"}

      SSE

      response = streamer.finalize

      expect(texts).to eq(['Hello', ' world'])
      expect(response).to be_a(RubynCode::LLM::Response)
      expect(response.id).to eq('msg_1')
      expect(response.text).to eq('Hello world')
      expect(response.stop_reason).to eq('end_turn')
      expect(response.usage.input_tokens).to eq(10)
      expect(response.usage.output_tokens).to eq(5)
    end
  end

  describe 'tool use streaming' do
    it 'assembles tool_use blocks from input_json_delta events' do
      streamer = described_class.new

      streamer.feed(<<~SSE)
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_2","usage":{"input_tokens":20,"output_tokens":0}}}

      SSE

      streamer.feed(<<~SSE)
        event: content_block_start
        data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"read_file"}}

      SSE

      streamer.feed(<<~SSE)
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\\"path\\":"}}

      SSE

      streamer.feed(<<~SSE)
        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\\"foo.rb\\"}"}}

      SSE

      streamer.feed(<<~SSE)
        event: content_block_stop
        data: {"type":"content_block_stop","index":0}

      SSE

      streamer.feed(<<~SSE)
        event: message_delta
        data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":15}}

      SSE

      streamer.feed(<<~SSE)
        event: message_stop
        data: {"type":"message_stop"}

      SSE

      response = streamer.finalize

      expect(response.tool_use?).to be true
      tool = response.tool_calls.first
      expect(tool.name).to eq('read_file')
      expect(tool.input).to eq({ 'path' => 'foo.rb' })
    end
  end

  describe 'error handling' do
    it 'raises OverloadError on overloaded_error' do
      streamer = described_class.new

      expect do
        streamer.feed(<<~SSE)
          event: error
          data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}

        SSE
      end.to raise_error(described_class::OverloadError, 'Overloaded')
    end

    it 'raises ParseError on other streaming errors' do
      streamer = described_class.new

      expect do
        streamer.feed(<<~SSE)
          event: error
          data: {"type":"error","error":{"type":"server_error","message":"Internal error"}}

        SSE
      end.to raise_error(described_class::ParseError, /Internal error/)
    end
  end

  describe 'backward compatibility' do
    it 'is aliased as LLM::Streaming' do
      expect(RubynCode::LLM::Streaming).to eq(described_class)
    end
  end
end
