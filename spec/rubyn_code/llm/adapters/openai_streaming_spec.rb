# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubynCode::LLM::Adapters::OpenAIStreaming do
  describe 'text streaming' do
    it 'assembles text from content deltas and skips empty strings' do
      texts = []
      streamer = described_class.new do |event|
        texts << event.data[:text] if event.type == :text_delta
      end

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-1","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}],"usage":null}

      SSE

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-1","model":"gpt-4o","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}],"usage":null}

      SSE

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-1","model":"gpt-4o","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}],"usage":null}

      SSE

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-1","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":null}

      SSE

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-1","usage":{"prompt_tokens":10,"completion_tokens":5}}

      SSE

      streamer.feed("data: [DONE]\n\n")

      response = streamer.finalize

      expect(texts).to eq(['Hello', ' world'])
      expect(response).to be_a(RubynCode::LLM::Response)
      expect(response.id).to eq('chatcmpl-1')
      expect(response.text).to eq('Hello world')
      expect(response.stop_reason).to eq('end_turn')
      expect(response.usage.input_tokens).to eq(10)
      expect(response.usage.output_tokens).to eq(5)
    end
  end

  describe 'tool call streaming' do
    it 'assembles tool_use blocks from tool_calls deltas' do
      streamer = described_class.new

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-2","model":"gpt-4o","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":""}}]},"finish_reason":null}]}

      SSE

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-2","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"path\\":"}}]},"finish_reason":null}]}

      SSE

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-2","model":"gpt-4o","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\\"foo.rb\\"}"}}]},"finish_reason":null}]}

      SSE

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-2","model":"gpt-4o","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

      SSE

      streamer.feed("data: [DONE]\n\n")

      response = streamer.finalize

      expect(response.stop_reason).to eq('tool_use')
      expect(response.tool_use?).to be true
      tool = response.tool_calls.first
      expect(tool.name).to eq('read_file')
      expect(tool.input).to eq({ 'path' => 'foo.rb' })
    end
  end

  describe 'multiple tool calls' do
    it 'handles parallel tool calls at different indices' do
      streamer = described_class.new

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-3","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"id":"call_a","type":"function","function":{"name":"read_file","arguments":""}},{"index":1,"id":"call_b","type":"function","function":{"name":"glob","arguments":""}}]},"finish_reason":null}]}

      SSE

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-3","choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\\"path\\":\\"a.rb\\"}"}},{"index":1,"function":{"arguments":"{\\"pattern\\":\\"*.rb\\"}"}}]},"finish_reason":null}]}

      SSE

      streamer.feed(<<~SSE)
        data: {"id":"chatcmpl-3","choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

      SSE

      streamer.feed("data: [DONE]\n\n")

      response = streamer.finalize

      expect(response.tool_calls.size).to eq(2)
      expect(response.tool_calls[0].name).to eq('read_file')
      expect(response.tool_calls[0].input).to eq({ 'path' => 'a.rb' })
      expect(response.tool_calls[1].name).to eq('glob')
      expect(response.tool_calls[1].input).to eq({ 'pattern' => '*.rb' })
    end
  end

  describe 'stop reason normalization' do
    it 'maps stop to end_turn' do
      streamer = described_class.new
      streamer.feed("data: {\"id\":\"x\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n")
      streamer.feed("data: [DONE]\n\n")
      expect(streamer.finalize.stop_reason).to eq('end_turn')
    end

    it 'maps length to max_tokens' do
      streamer = described_class.new
      streamer.feed("data: {\"id\":\"x\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"length\"}]}\n\n")
      streamer.feed("data: [DONE]\n\n")
      expect(streamer.finalize.stop_reason).to eq('max_tokens')
    end

    it 'maps tool_calls to tool_use' do
      streamer = described_class.new
      streamer.feed("data: {\"id\":\"x\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n")
      streamer.feed("data: [DONE]\n\n")
      expect(streamer.finalize.stop_reason).to eq('tool_use')
    end
  end

  describe '[DONE] handling' do
    it 'does not raise on [DONE] sentinel' do
      streamer = described_class.new
      expect { streamer.feed("data: [DONE]\n\n") }.not_to raise_error
    end
  end
end
