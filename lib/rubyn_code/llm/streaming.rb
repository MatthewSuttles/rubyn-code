# frozen_string_literal: true

module RubynCode
  module LLM
    class Streaming
      class ParseError < RubynCode::Error
      end

      class OverloadError < RubynCode::Error
      end

      Event = Data.define(:type, :data)

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

      # Feed raw SSE data chunk from the HTTP response body.
      def feed(chunk)
        @buffer << chunk
        consume_events
      end

      # Returns the fully assembled Response once the stream completes.
      def finalize
        Response.new(
          id: @response_id,
          content: build_content_blocks,
          stop_reason: @stop_reason,
          usage: @usage
        )
      end

      HANDLERS = {
        'message_start' => :handle_message_start,
        'content_block_start' => :handle_content_block_start,
        'content_block_delta' => :handle_content_block_delta,
        'content_block_stop' => :handle_content_block_stop,
        'message_delta' => :handle_message_delta,
        'message_stop' => :handle_message_stop,
        'error' => :handle_error
      }.freeze

      private

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

      def handle_message_start(data)
        message = data['message'] || data
        @response_id = message['id']

        if (u = message['usage'])
          @usage = Usage.new(
            input_tokens: u['input_tokens'].to_i,
            output_tokens: u['output_tokens'].to_i,
            cache_creation_input_tokens: u['cache_creation_input_tokens'].to_i,
            cache_read_input_tokens: u['cache_read_input_tokens'].to_i
          )
        end

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
        index = data['index'].to_i

        if @current_tool_id
          input = parse_json(@current_tool_input_json)
          @content_blocks[index] = ToolUseBlock.new(
            id: @current_tool_id,
            name: @current_tool_name,
            input: input || {}
          )
          @current_tool_id = nil
          @current_tool_name = nil
          @current_tool_input_json = +''
        else
          @content_blocks[index] = TextBlock.new(text: @current_text.dup)
          @current_text = +''
        end

        emit(:content_block_stop, data)
      end

      def handle_message_delta(data)
        delta = data['delta'] || {}
        @stop_reason = delta['stop_reason'] if delta['stop_reason']
        update_usage_from_delta(data['usage']) if data['usage']
        emit(:message_delta, data)
      end

      def update_usage_from_delta(usage_data)
        @usage = Usage.new(
          input_tokens: @usage&.input_tokens || 0,
          output_tokens: usage_data['output_tokens'].to_i,
          cache_creation_input_tokens: @usage&.cache_creation_input_tokens || 0,
          cache_read_input_tokens: @usage&.cache_read_input_tokens || 0
        )
      end

      def handle_message_stop
        flush_pending_block
        emit(:message_stop, {})
      end

      def handle_error(data)
        error = data['error'] || data
        error_type = error['type'] || 'unknown'
        message = error['message'] || 'Unknown streaming error'

        raise OverloadError, message if error_type == 'overloaded_error'

        raise ParseError, "Streaming error (#{error_type}): #{message}"
      end

      def emit(type, data)
        @callback&.call(Event.new(type: type, data: data))
      end

      def flush_pending_block
        return unless @current_block_index

        if @current_tool_id
          input = parse_json(@current_tool_input_json) || {}
          @content_blocks[@current_block_index] = ToolUseBlock.new(
            id: @current_tool_id,
            name: @current_tool_name,
            input: input
          )
          @current_tool_id = nil
          @current_tool_name = nil
          @current_tool_input_json = +''
        elsif !@current_text.empty?
          @content_blocks[@current_block_index] = TextBlock.new(text: @current_text.dup)
          @current_text = +''
        end

        @current_block_index = nil
      end

      def build_content_blocks
        @content_blocks.compact
      end

      def parse_json(str)
        return nil if str.nil? || str.strip.empty?

        JSON.parse(str)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
