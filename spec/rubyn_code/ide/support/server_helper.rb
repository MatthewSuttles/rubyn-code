# frozen_string_literal: true

require "stringio"
require "json"
require "timeout"

module IDEServerHelper
  # Build a test server that reads from the given StringIO input
  # and writes to the given StringIO output, instead of $stdin/$stdout.
  def build_test_server(stdin_io, stdout_io)
    server = RubynCode::IDE::Server.new

    # Override the server's private write method to use our StringIO
    server.define_singleton_method(:write) do |hash|
      serialized = RubynCode::IDE::Protocol.serialize(hash)
      @test_write_mutex ||= Mutex.new
      @test_write_mutex.synchronize do
        stdout_io.write(serialized)
        stdout_io.flush
      end
    end

    # Override read_loop to read from our StringIO instead of $stdin
    server.define_singleton_method(:read_loop) do
      while @running
        line = stdin_io.gets
        break if line.nil?

        line = line.strip
        next if line.empty?

        handle_line(line)
      end
    end

    # Make handle_line accessible
    server.define_singleton_method(:public_handle_line) do |line|
      send(:handle_line, line)
    end

    server
  end

  # Write a JSON-RPC request to the given IO
  def send_request(io, method, params = {}, id: 1)
    msg = {
      "jsonrpc" => "2.0",
      "id"      => id,
      "method"  => method,
      "params"  => params
    }
    io.puts(JSON.generate(msg))
  end

  # Write a JSON-RPC notification (no id) to the given IO
  def send_notification(io, method, params = {})
    msg = {
      "jsonrpc" => "2.0",
      "method"  => method,
      "params"  => params
    }
    io.puts(JSON.generate(msg))
  end

  # Read and parse a single JSON-RPC message from the IO.
  # Returns nil if no data available.
  def read_response(io)
    io.rewind if io.respond_to?(:rewind) && io.pos == 0
    line = io.gets
    return nil unless line

    JSON.parse(line.strip)
  rescue JSON::ParserError
    nil
  end

  # Read all available messages from the IO within the given timeout.
  def read_all_messages(io, timeout: 1)
    messages = []
    io.rewind if io.respond_to?(:rewind)

    Timeout.timeout(timeout) do
      while (line = io.gets)
        line = line.strip
        next if line.empty?

        begin
          messages << JSON.parse(line)
        rescue JSON::ParserError
          next
        end
      end
    end

    messages
  rescue Timeout::Error
    messages
  end

  # A mock agent loop that emits predictable notifications.
  class MockAgentLoop
    attr_reader :messages_sent

    def initialize
      @messages_sent = []
    end

    def send_message(input)
      @messages_sent << input
      "Mock response to: #{input}"
    end
  end
end
