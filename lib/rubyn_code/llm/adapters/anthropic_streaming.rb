# frozen_string_literal: true

require_relative '../message_builder'

module RubynCode
  module LLM
    module Adapters
      # SSE streaming parser for the Anthropic Messages API.
      #
      # Handles Anthropic-specific event types: message_start, content_block_start,
      # content_block_delta, content_block_stop, message_delta, message_stop, error.
      # Accumulates content blocks and produces a normalized LLM::Response via #finalize.
      class AnthropicStreaming
        include JsonParsing

        class ParseError < RubynCode::Error; end
        class OverloadError < RubynCode::Error; end

        Event = Data.define(:type, :data)

        HANDLERS = {
          'message_start' => :handle_message_start,
          'content_block_start' => :handle_content_block_start,
          'content_block_delta' => :handle_content_block_delta,
          'content_block_stop' => :handle_content_block_stop,
          'message_delta' => :handle_message_delta,
          'message_stop' => :handle_message_stop,
          'error' => :handle_error
        }.freeze

        def initialize(&block)
          @callback = block
          @buffer = +''
          @response_id = nil
          @content_blocks = []
          @current_block_index = nil
          @current_text = +''
          @current_tool_input_json = +''
          @stop_reason = nil
          @usage = nil
        end

        def feed(chunk)
          @buffer << chunk
          consume_events
        end

        def finalize
          flush_pending_block
          Response.new(
            id: @response_id,
            content: @content_blocks.compact,
            stop_reason: @stop_reason,
            usage: @usage
          )
        end

        private

        # -- SSE parsing --------------------------------------------------

        def consume_events
          while (idx = @buffer.index("\n\n"))
            raw_event = @buffer.slice!(0..(idx + 1))
            parse_sse(raw_event)
          end
        end

        def parse_sse(raw)
          event_type = nil
          data_lines = []

          raw.each_line do |line|
            line = line.chomp
            case line
            when /\Aevent:\s*(.+)/ then event_type = ::Regexp.last_match(1).strip
            when /\Adata:\s*(.*)/ then data_lines << ::Regexp.last_match(1)
            end
          end

          return if data_lines.empty? && event_type.nil?

          data_str = data_lines.join("\n")
          dispatch(event_type, data_str.empty? ? {} : parse_json(data_str))
        end

        def dispatch(event_type, data)
          handler = HANDLERS[event_type]
          return unless handler

          method(handler).arity.zero? ? send(handler) : send(handler, data)
        end

        # -- Event handlers -----------------------------------------------

        def handle_message_start(data)
          message = data['message'] || data
          @response_id = message['id']
          @usage = build_usage(message['usage']) if message['usage']
          emit(:message_start, data)
        end

        def handle_content_block_start(data)
          @current_block_index = data['index']
          block = data['content_block'] || {}

          case block['type']
          when 'text'
            @current_text = +(block['text'] || '')
          when 'tool_use'
            @current_tool_id = block['id']
            @current_tool_name = block['name']
            @current_tool_input_json = +''
          end

          emit(:content_block_start, data)
        end

        def handle_content_block_delta(data)
          delta = data['delta'] || {}

          case delta['type']
          when 'text_delta'
            text = delta['text'] || ''
            @current_text << text
            emit(:text_delta, { index: data['index'], text: text })
          when 'input_json_delta'
            json_chunk = delta['partial_json'] || ''
            @current_tool_input_json << json_chunk
            emit(:input_json_delta, { index: data['index'], partial_json: json_chunk })
          end

          emit(:content_block_delta, data)
        end

        def handle_content_block_stop(data)
          store_current_block(data['index'].to_i)
          emit(:content_block_stop, data)
        end

        def handle_message_delta(data)
          delta = data['delta'] || {}
          @stop_reason = delta['stop_reason'] if delta['stop_reason']
          update_output_tokens(data['usage']) if data['usage']
          emit(:message_delta, data)
        end

        def handle_message_stop
          emit(:message_stop, {})
        end

        def handle_error(data)
          error = data['error'] || data
          error_type = error['type'] || 'unknown'
          message = error['message'] || 'Unknown streaming error'

          raise OverloadError, message if error_type == 'overloaded_error'

          raise ParseError, "Streaming error (#{error_type}): #{message}"
        end

        # -- Block assembly (single code path) ----------------------------

        def store_current_block(index)
          if @current_tool_id
            @content_blocks[index] = build_tool_block
          elsif !@current_text.empty?
            @content_blocks[index] = TextBlock.new(text: @current_text.dup)
            @current_text = +''
          end
        end

        def flush_pending_block
          return unless @current_block_index

          store_current_block(@current_block_index)
          @current_block_index = nil
        end

        def build_tool_block
          input = parse_json(@current_tool_input_json) || {}
          block = ToolUseBlock.new(id: @current_tool_id, name: @current_tool_name, input: input)
          @current_tool_id = nil
          @current_tool_name = nil
          @current_tool_input_json = +''
          block
        end

        # -- Helpers ------------------------------------------------------

        def build_usage(data)
          Usage.new(
            input_tokens: data['input_tokens'].to_i,
            output_tokens: data['output_tokens'].to_i,
            cache_creation_input_tokens: data['cache_creation_input_tokens'].to_i,
            cache_read_input_tokens: data['cache_read_input_tokens'].to_i
          )
        end

        def update_output_tokens(usage_data)
          @usage = Usage.new(
            input_tokens: @usage&.input_tokens || 0,
            output_tokens: usage_data['output_tokens'].to_i,
            cache_creation_input_tokens: @usage&.cache_creation_input_tokens || 0,
            cache_read_input_tokens: @usage&.cache_read_input_tokens || 0
          )
        end

        def emit(type, data)
          @callback&.call(Event.new(type: type, data: data))
        end
      end
    end
  end
end
