# frozen_string_literal: true

require "json"
require "open3"
require "timeout"

module RubynCode
  module MCP
    # Communicates with an MCP server via subprocess stdin/stdout using JSON-RPC 2.0.
    #
    # The server process is spawned with Open3.popen3 and kept alive for the
    # duration of the session. Requests are written as newline-delimited JSON
    # to stdin, and responses are read line-by-line from stdout.
    class StdioTransport
      DEFAULT_TIMEOUT = 30 # seconds

      TransportError = Class.new(RubynCode::Error)
      TimeoutError = Class.new(TransportError)

      # @param command [String] executable to spawn
      # @param args [Array<String>] arguments for the command
      # @param env [Hash<String, String>] additional environment variables
      # @param timeout [Integer] default timeout in seconds per request
      def initialize(command:, args: [], env: {}, timeout: DEFAULT_TIMEOUT)
        @command = command
        @args = args
        @env = env
        @timeout = timeout
        @request_id = 0
        @mutex = Mutex.new
        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thread = nil
      end

      # Spawns the MCP server subprocess.
      #
      # @return [void]
      # @raise [TransportError] if the process fails to start
      def start!
        raise TransportError, "Transport already started" if alive?

        @stdin, @stdout, @stderr, @wait_thread = Open3.popen3(@env, @command, *@args)
      rescue Errno::ENOENT => e
        raise TransportError, "Failed to start MCP server: #{e.message}"
      end

      # Sends a JSON-RPC 2.0 request and waits for the correlated response.
      #
      # @param method [String] the JSON-RPC method name
      # @param params [Hash] parameters for the request
      # @return [Hash] the parsed JSON-RPC response result
      # @raise [TransportError] on protocol or server errors
      # @raise [TimeoutError] if the response is not received within the timeout
      def send_request(method, params = {})
        raise TransportError, "Transport is not running" unless alive?

        id = next_request_id
        request = {
          jsonrpc: "2.0",
          id: id,
          method: method,
          params: params
        }

        write_request(request)
        read_response(id)
      end

      # Sends a JSON-RPC 2.0 notification (no response expected).
      #
      # @param method [String] the JSON-RPC method name
      # @param params [Hash] parameters for the notification
      # @return [void]
      def send_notification(method, params = {})
        raise TransportError, "Transport is not running" unless alive?

        notification = {
          jsonrpc: "2.0",
          method: method,
          params: params
        }

        write_request(notification)
      end

      # Gracefully shuts down the MCP server and cleans up resources.
      #
      # @return [void]
      def stop!
        return unless alive?

        begin
          send_notification("notifications/cancelled")
          @stdin&.close
        rescue IOError, Errno::EPIPE
          # Process may already be gone
        end

        begin
          @wait_thread&.join(5)
        rescue StandardError
          # Best-effort wait
        end

        force_kill if alive?
      ensure
        close_streams
      end

      # Checks whether the subprocess is still running.
      #
      # @return [Boolean]
      def alive?
        return false unless @wait_thread

        @wait_thread.alive?
      end

      private

      def next_request_id
        @mutex.synchronize { @request_id += 1 }
      end

      def write_request(request)
        @mutex.synchronize do
          data = JSON.generate(request)
          @stdin.write("#{data}\n")
          @stdin.flush
        end
      rescue IOError, Errno::EPIPE => e
        raise TransportError, "Failed to write to MCP server: #{e.message}"
      end

      def read_response(expected_id)
        Timeout.timeout(@timeout, TimeoutError, "MCP server did not respond within #{@timeout}s") do
          loop do
            line = @stdout.gets
            raise TransportError, "MCP server closed stdout unexpectedly" if line.nil?

            line = line.strip
            next if line.empty?

            message = parse_json(line)
            next unless message

            # Skip notifications (no id field)
            next unless message.key?("id")

            # Skip responses for other requests
            next unless message["id"] == expected_id

            if message.key?("error")
              err = message["error"]
              raise TransportError, "MCP error (#{err['code']}): #{err['message']}"
            end

            return message["result"]
          end
        end
      end

      def parse_json(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end

      def force_kill
        return unless @wait_thread

        pid = @wait_thread.pid
        Process.kill("TERM", pid)
        sleep(0.5)
        Process.kill("KILL", pid) if @wait_thread.alive?
      rescue Errno::ESRCH, Errno::EPERM
        # Process already gone or we lack permissions
      end

      def close_streams
        [@stdin, @stdout, @stderr].each do |stream|
          stream&.close unless stream&.closed?
        rescue IOError
          # Already closed
        end

        @stdin = nil
        @stdout = nil
        @stderr = nil
        @wait_thread = nil
      end
    end
  end
end
