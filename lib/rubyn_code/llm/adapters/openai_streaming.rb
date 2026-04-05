# frozen_string_literal: true

require_relative '../message_builder'

module RubynCode
  module LLM
    module Adapters
      # SSE streaming parser for OpenAI Chat Completions API.
      #
      # Parses `data: {...}` lines from the SSE stream, accumulates content deltas
      # and tool_calls, and produces a normalized LLM::Response via #finalize.
      class OpenAIStreaming
        include JsonParsing

        Event = Data.define(:type, :data)

        STOP_REASON_MAP = {
          'stop' => 'end_turn',
          'tool_calls' => 'tool_use',
          'length' => 'max_tokens',
          'content_filter' => 'end_turn'
        }.freeze

        def initialize(&block)
          @callback = block
          @buffer = +''
          @content_text = +''
          @tool_calls = {}
          @response_id = nil
          @model = nil
          @finish_reason = nil
          @usage = nil
        end

        def feed(chunk)
          @buffer << chunk
          consume_sse_events
        end

        def finalize
          content = build_content_blocks
          stop = STOP_REASON_MAP[@finish_reason] || @finish_reason || 'end_turn'

          RubynCode::LLM::Response.new(
            id: @response_id,
            content: content,
            stop_reason: stop,
            usage: @usage || RubynCode::LLM::Usage.new(input_tokens: 0, output_tokens: 0)
          )
        end

        private

        def consume_sse_events
          while (idx = @buffer.index("\n\n"))
            line = @buffer.slice!(0..(idx + 1)).strip
            process_sse_line(line)
          end
        end

        def process_sse_line(line)
          return unless line.start_with?('data: ')

          payload = line.sub('data: ', '')
          return if payload == '[DONE]'

          data = parse_json(payload)
          return unless data

          handle_chunk(data)
        end

        def handle_chunk(data)
          @response_id ||= data['id']
          @model ||= data['model']
          extract_usage(data)

          choice = data.dig('choices', 0)
          return unless choice

          @finish_reason = choice['finish_reason'] if choice['finish_reason']
          process_delta(choice['delta'] || {})
        end

        def extract_usage(data)
          return unless data['usage']

          @usage = RubynCode::LLM::Usage.new(
            input_tokens: data['usage']['prompt_tokens'].to_i,
            output_tokens: data['usage']['completion_tokens'].to_i
          )
        end

        def process_delta(delta)
          handle_content_delta(delta['content']) if delta.key?('content')
          handle_tool_calls_delta(delta['tool_calls']) if delta['tool_calls']
        end

        def handle_content_delta(text)
          return if text.nil? || text.empty?

          @content_text << text
          @callback&.call(Event.new(type: :text_delta, data: { text: text }))
        end

        def handle_tool_calls_delta(tool_calls)
          tool_calls.each { |tool_call| accumulate_tool_call(tool_call) }
        end

        def accumulate_tool_call(tool_call)
          idx = tool_call['index']
          @tool_calls[idx] ||= { id: nil, name: +'', arguments: +'' }

          entry = @tool_calls[idx]
          entry[:id] = tool_call['id'] if tool_call['id']
          merge_function_delta(entry, tool_call['function'])
        end

        def merge_function_delta(entry, func)
          return unless func

          entry[:name] << func['name'].to_s
          entry[:arguments] << func['arguments'].to_s
        end

        def build_content_blocks
          blocks = []
          blocks << RubynCode::LLM::TextBlock.new(text: @content_text) unless @content_text.empty?

          @tool_calls.keys.sort.each do |idx|
            entry = @tool_calls[idx]
            input = parse_json(entry[:arguments]) || {}
            blocks << RubynCode::LLM::ToolUseBlock.new(id: entry[:id], name: entry[:name], input: input)
          end

          blocks
        end
      end
    end
  end
end
