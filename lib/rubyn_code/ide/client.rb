# frozen_string_literal: true

require 'securerandom'

module RubynCode
  module IDE
    # Sends JSON-RPC requests from the CLI server to the VS Code extension
    # and awaits responses. Enables the CLI to ask the IDE to do things like
    # open diffs, read diagnostics, or navigate to a file.
    #
    # Uses the server's write mutex for thread-safe output. Tracks pending
    # responses via a { id => ConditionVariable } map.
    class Client
      DEFAULT_TIMEOUT = 30 # seconds

      def initialize(server)
        @server = server
        @mutex = Mutex.new
        @next_id = 1000 # Start high to avoid collisions with client IDs
        @pending = {} # { id => { cv: ConditionVariable, result: nil, error: nil } }
      end

      # Send a JSON-RPC request to the extension and block until the response
      # arrives or the timeout expires.
      #
      # @param method [String] the RPC method name (e.g. "ide/readSelection")
      # @param params [Hash] the request params
      # @param timeout [Numeric] seconds to wait for a response
      # @return [Hash] the result from the extension
      # @raise [TimeoutError] if no response within timeout
      # @raise [StandardError] if the extension returns an RPC error
      def request(method, params = {}, timeout: DEFAULT_TIMEOUT)
        id = allocate_id
        cv = ConditionVariable.new

        @mutex.synchronize do
          @pending[id] = { cv: cv, result: nil, error: nil }
        end

        # Write the request via the server's write path
        write_raw({
          'jsonrpc' => Protocol::JSONRPC_VERSION,
          'id' => id,
          'method' => method,
          'params' => Protocol.send(:stringify_keys_deep, params)
        })

        # Block until the extension responds or we time out
        @mutex.synchronize do
          deadline = Time.now + timeout
          while @pending[id][:result].nil? && @pending[id][:error].nil?
            remaining = deadline - Time.now
            if remaining <= 0
              @pending.delete(id)
              raise TimeoutError, "IDE RPC request '#{method}' timed out after #{timeout}s"
            end
            cv.wait(@mutex, remaining)
          end

          entry = @pending.delete(id)
          raise StandardError, entry[:error] if entry[:error]

          entry[:result]
        end
      end

      # Called by the server when it receives a response message (has id + result/error,
      # no method) that matches one of our pending outbound requests.
      #
      # @param id [Integer] the response id
      # @param result [Hash, nil] the result payload
      # @param error [Hash, nil] the error payload
      def resolve(id, result: nil, error: nil)
        @mutex.synchronize do
          entry = @pending[id]
          return unless entry

          if error
            entry[:error] = "RPC error #{error['code']}: #{error['message']}"
          else
            entry[:result] = result || {}
          end
          entry[:cv].signal
        end
      end

      # Check if we have a pending request with this id.
      def pending?(id)
        @mutex.synchronize { @pending.key?(id) }
      end

      private

      def allocate_id
        @mutex.synchronize do
          id = @next_id
          @next_id += 1
          id
        end
      end

      # Write using the server's write method for thread-safe, testable output.
      def write_raw(msg_hash)
        @server.send(:write, msg_hash)
      end

      class TimeoutError < StandardError; end
    end
  end
end
