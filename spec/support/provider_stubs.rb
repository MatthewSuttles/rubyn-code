# frozen_string_literal: true

# Stubbed HTTP response builders for each LLM provider.
#
# These generate realistic API responses that match what Anthropic, OpenAI,
# and OpenAI-compatible endpoints actually return. Used by integration tests
# to verify full round-trip behavior without hitting real APIs.
module ProviderStubs
  # ---------------------------------------------------------------------------
  # Shared SSE helpers
  # ---------------------------------------------------------------------------
  module SSE
    module_function

    def sse_event(event_type, data)
      "event: #{event_type}\ndata: #{JSON.generate(data)}\n\n"
    end

    def openai_sse_chunk(id, delta, finish_reason: nil, usage: nil)
      chunk = {
        'id' => id,
        'object' => 'chat.completion.chunk',
        'choices' => [{ 'index' => 0, 'delta' => delta }]
      }
      chunk['choices'][0]['finish_reason'] = finish_reason if finish_reason
      chunk['usage'] = usage if usage
      "data: #{JSON.generate(chunk)}\n\n"
    end
  end

  # ---------------------------------------------------------------------------
  # Anthropic response builders
  # ---------------------------------------------------------------------------
  module Anthropic
    include SSE

    module_function

    def anthropic_text_response(text, id: 'msg_ant_001')
      {
        'id' => id,
        'type' => 'message',
        'role' => 'assistant',
        'content' => [{ 'type' => 'text', 'text' => text }],
        'stop_reason' => 'end_turn',
        'usage' => { 'input_tokens' => 42, 'output_tokens' => 17 }
      }
    end

    def anthropic_tool_use_response(tool_name:, tool_input:, tool_id: 'toolu_ant_001', id: 'msg_ant_002',
                                    text_prefix: nil)
      content = []
      content << { 'type' => 'text', 'text' => text_prefix } if text_prefix
      content << { 'type' => 'tool_use', 'id' => tool_id, 'name' => tool_name, 'input' => tool_input }
      {
        'id' => id,
        'type' => 'message',
        'role' => 'assistant',
        'content' => content,
        'stop_reason' => 'tool_use',
        'usage' => { 'input_tokens' => 50, 'output_tokens' => 30 }
      }
    end

    def anthropic_stream_events(text, id: 'msg_ant_stream_001')
      [
        sse_event('message_start', {
                    'type' => 'message_start',
                    'message' => {
                      'id' => id, 'type' => 'message', 'role' => 'assistant',
                      'usage' => { 'input_tokens' => 25, 'output_tokens' => 0 }
                    }
                  }),
        sse_event('content_block_start', {
                    'type' => 'content_block_start', 'index' => 0,
                    'content_block' => { 'type' => 'text', 'text' => '' }
                  }),
        sse_event('content_block_delta', {
                    'type' => 'content_block_delta', 'index' => 0,
                    'delta' => { 'type' => 'text_delta', 'text' => text }
                  }),
        sse_event('content_block_stop', { 'type' => 'content_block_stop', 'index' => 0 }),
        sse_event('message_delta', {
                    'type' => 'message_delta',
                    'delta' => { 'stop_reason' => 'end_turn' },
                    'usage' => { 'output_tokens' => 12 }
                  }),
        sse_event('message_stop', { 'type' => 'message_stop' })
      ].join
    end

    def anthropic_stream_tool_use_events(tool_name:, tool_input_json:, tool_id: 'toolu_ant_s01',
                                         id: 'msg_ant_stream_002')
      [
        sse_event('message_start', {
                    'type' => 'message_start',
                    'message' => {
                      'id' => id, 'type' => 'message', 'role' => 'assistant',
                      'usage' => { 'input_tokens' => 30, 'output_tokens' => 0 }
                    }
                  }),
        sse_event('content_block_start', {
                    'type' => 'content_block_start', 'index' => 0,
                    'content_block' => { 'type' => 'tool_use', 'id' => tool_id, 'name' => tool_name }
                  }),
        sse_event('content_block_delta', {
                    'type' => 'content_block_delta', 'index' => 0,
                    'delta' => { 'type' => 'input_json_delta', 'partial_json' => tool_input_json }
                  }),
        sse_event('content_block_stop', { 'type' => 'content_block_stop', 'index' => 0 }),
        sse_event('message_delta', {
                    'type' => 'message_delta',
                    'delta' => { 'stop_reason' => 'tool_use' },
                    'usage' => { 'output_tokens' => 20 }
                  }),
        sse_event('message_stop', { 'type' => 'message_stop' })
      ].join
    end

    def anthropic_error_response(status, type: 'api_error', message: 'Something went wrong')
      [status, { 'error' => { 'type' => type, 'message' => message } }]
    end
  end

  # ---------------------------------------------------------------------------
  # OpenAI response builders
  # ---------------------------------------------------------------------------
  module OpenAI
    include SSE

    module_function

    def openai_text_response(text, id: 'chatcmpl-oai001')
      {
        'id' => id,
        'object' => 'chat.completion',
        'choices' => [{
          'index' => 0,
          'message' => { 'role' => 'assistant', 'content' => text },
          'finish_reason' => 'stop'
        }],
        'usage' => { 'prompt_tokens' => 42, 'completion_tokens' => 17 }
      }
    end

    def openai_tool_call_response(tool_name:, tool_input:, tool_id: 'call_oai001', id: 'chatcmpl-oai002',
                                  text_content: nil)
      message = { 'role' => 'assistant' }
      message['content'] = text_content if text_content
      message['tool_calls'] = [{
        'id' => tool_id,
        'type' => 'function',
        'function' => { 'name' => tool_name, 'arguments' => JSON.generate(tool_input) }
      }]
      {
        'id' => id,
        'object' => 'chat.completion',
        'choices' => [{ 'index' => 0, 'message' => message, 'finish_reason' => 'tool_calls' }],
        'usage' => { 'prompt_tokens' => 50, 'completion_tokens' => 30 }
      }
    end

    def openai_stream_events(text, id: 'chatcmpl-oai-s01')
      [
        openai_sse_chunk(id, { 'content' => text }),
        openai_sse_chunk(id, {}, finish_reason: 'stop',
                                 usage: { 'prompt_tokens' => 25, 'completion_tokens' => 12 }),
        "data: [DONE]\n\n"
      ].join
    end

    def openai_stream_tool_use_events(tool_name:, tool_input_json:, tool_id: 'call_oai_s01',
                                      id: 'chatcmpl-oai-s02')
      [
        openai_sse_chunk(id, { 'tool_calls' => [{
                           'index' => 0, 'id' => tool_id, 'type' => 'function',
                           'function' => { 'name' => tool_name, 'arguments' => '' }
                         }] }),
        openai_sse_chunk(id, { 'tool_calls' => [{
                           'index' => 0,
                           'function' => { 'arguments' => tool_input_json }
                         }] }),
        openai_sse_chunk(id, {}, finish_reason: 'tool_calls',
                                 usage: { 'prompt_tokens' => 30, 'completion_tokens' => 20 }),
        "data: [DONE]\n\n"
      ].join
    end

    def openai_error_response(status, message: 'Something went wrong')
      [status, { 'error' => { 'message' => message, 'type' => 'invalid_request_error' } }]
    end
  end

  include Anthropic
  include OpenAI
  include SSE
end

RSpec.configure do |config|
  config.include ProviderStubs
end
