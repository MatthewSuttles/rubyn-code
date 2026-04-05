# frozen_string_literal: true

require 'faraday'
require 'json'
require 'uri'

module RubynCode
  module MCP
    # Communicates with a remote MCP server via HTTP Server-Sent Events (SSE).
    #
    # On #start!, the transport establishes a long-lived GET connection to the
    # SSE endpoint. The server responds with an `endpoint` event containing
    # the URL for JSON-RPC POST requests. Subsequent requests are sent via
    # POST, and responses arrive as SSE events on the GET stream.
    class SSETransport
      DEFAULT_TIMEOUT = 30 # seconds

      class TransportError < RubynCode::Error
      end

      class TimeoutError < TransportError
      end

      # @param url [String] the SSE endpoint URL of the MCP server
      # @param timeout [Integer] default timeout in seconds per request
      def initialize(url:, timeout: DEFAULT_TIMEOUT)
        @url = url
        @timeout = timeout
        @request_id = 0
        @mutex = Mutex.new
        @post_endpoint = nil
        @pending_responses = {}
        @connected = false
        @sse_thread = nil
      end

      # Establishes the SSE connection and waits for the endpoint event.
      #
      # @return [void]
      # @raise [TransportError] if the connection cannot be established
      def start!
        raise TransportError, 'Transport already started' if @connected

        @pending_responses = {}
        @sse_thread = Thread.new { run_sse_listener }

        # Wait for the endpoint event with a timeout
        deadline = Time.now + @timeout
        sleep(0.1) until @post_endpoint || Time.now > deadline

        unless @post_endpoint
          stop!
          raise TransportError, "MCP server did not provide an endpoint within #{@timeout}s"
        end

        @connected = true
      end

      # Sends a JSON-RPC 2.0 request via HTTP POST and waits for the response.
      #
      # @param method [String] the JSON-RPC method name
      # @param params [Hash] parameters for the request
      # @return [Hash] the parsed JSON-RPC result
      # @raise [TransportError] on protocol or server errors
      # @raise [TimeoutError] if the response is not received in time
      def send_request(method, params = {})
        raise TransportError, 'Transport is not connected' unless @connected

        id = next_request_id
        queue = Queue.new
        @mutex.synchronize { @pending_responses[id] = queue }

        request = {
          jsonrpc: '2.0',
          id: id,
          method: method,
          params: params
        }

        post_request(request)
        wait_for_response(id, queue)
      end

      # Closes the SSE connection and cleans up resources.
      #
      # @return [void]
      def stop!
        @connected = false
        @sse_thread&.kill
        @sse_thread = nil
        @post_endpoint = nil
        @pending_responses.clear
      end

      # Checks whether the transport is connected.
      #
      # @return [Boolean]
      def alive?
        @connected && @sse_thread&.alive?
      end

      private

      def next_request_id
        @mutex.synchronize { @request_id += 1 }
      end

      def base_url
        uri = URI.parse(@url)
        "#{uri.scheme}://#{uri.host}#{":#{uri.port}" if uri.port != uri.default_port}"
      end

      def connection
        @connection ||= Faraday.new(url: base_url) do |f|
          f.options.timeout = @timeout
          f.options.open_timeout = @timeout
          f.headers['Content-Type'] = 'application/json'
          f.adapter Faraday.default_adapter
        end
      end

      def post_request(request)
        response = connection.post(@post_endpoint) do |req|
          req.body = JSON.generate(request)
        end

        return if response.success?

        raise TransportError, "MCP server returned HTTP #{response.status}: #{response.body}"
      rescue Faraday::Error => e
        raise TransportError, "Failed to send request to MCP server: #{e.message}"
      end

      def wait_for_response(id, queue)
        result = nil
        begin
          Timeout.timeout(@timeout, TimeoutError, "MCP server did not respond within #{@timeout}s") do
            result = queue.pop
          end
        ensure
          @mutex.synchronize { @pending_responses.delete(id) }
        end

        if result.is_a?(Hash) && result.key?('error')
          err = result['error']
          raise TransportError, "MCP error (#{err['code']}): #{err['message']}"
        end

        result
      end

      def run_sse_listener
        conn = build_sse_connection
        buffer = +''

        conn.get(@url) do |req|
          req.options.on_data = proc do |chunk, _bytes, _env|
            buffer << chunk
            process_sse_buffer(buffer)
          end
        end
      rescue Faraday::Error => e
        @connected = false
        warn "[MCP::SSETransport] SSE connection lost: #{e.message}"
      end

      def build_sse_connection
        Faraday.new(url: base_url) do |f|
          f.options.timeout = nil
          f.options.open_timeout = @timeout
          f.headers['Accept'] = 'text/event-stream'
          f.adapter Faraday.default_adapter
        end
      end

      def process_sse_buffer(buffer)
        while (idx = buffer.index("\n\n"))
          raw_event = buffer.slice!(0, idx + 2)
          event = parse_sse_event(raw_event)
          handle_sse_event(event) if event
        end
      end

      def parse_sse_event(raw)
        event_type = nil
        data_lines = []

        raw.each_line do |line|
          line = line.chomp
          if line.start_with?('event:')
            event_type = line.sub('event:', '').strip
          elsif line.start_with?('data:')
            data_lines << line.sub('data:', '').strip
          end
        end

        return nil if data_lines.empty?

        { type: event_type, data: data_lines.join("\n") }
      end

      def handle_sse_event(event)
        if event[:type] == 'endpoint'
          @post_endpoint = event[:data]
        else
          dispatch_message(event[:data])
        end
      end

      def dispatch_message(data)
        message = JSON.parse(data)
        return unless message.is_a?(Hash) && message.key?('id')

        id = message['id']
        queue = @mutex.synchronize { @pending_responses[id] }
        return unless queue

        if message.key?('error')
          queue.push(message)
        else
          queue.push(message['result'])
        end
      rescue JSON::ParserError
        # Ignore malformed messages
      end
    end
  end
end
