# frozen_string_literal: true

require 'json'
require_relative 'protocol'
require_relative 'client'
require_relative 'handlers'

module RubynCode
  module IDE
    # JSON-RPC 2.0 server for the VS Code extension.
    #
    # Reads newline-delimited JSON from $stdin, dispatches each request
    # to a handler, and writes JSON-RPC responses/notifications to $stdout.
    # All debug output goes to $stderr — never protocol data.
    #
    # Processes one request at a time on the main thread.
    class Server
      # Attributes set by handlers during the session lifecycle.
      attr_accessor :workspace_path, :extension_version, :client_capabilities,
                    :session_persistence, :handler_instances, :tool_output_adapter,
                    :permission_mode
      attr_reader :ide_client

      def initialize(permission_mode: :default, yolo: false)
        @permission_mode = yolo ? :bypass : permission_mode.to_sym
        @running = false
        @write_mutex = Mutex.new
        @handlers = {}
        @handler_instances = {}
        @workspace_path = nil
        @extension_version = nil
        @client_capabilities = {}
        @session_persistence = nil
        @tool_output_adapter = nil
        @ide_client = Client.new(self)

        Handlers.register_all(self)
      end

      # Backward-compatible reader: true when permission_mode is :bypass.
      def yolo
        @permission_mode == :bypass
      end

      def run
        @running = true
        setup_signal_traps!

        warn "[IDE::Server] started (pid=#{Process.pid})"
        $stdout.sync = true

        read_loop
      ensure
        graceful_shutdown!
      end

      # ── Public helpers ──────────────────────────────────────────────

      # Send a JSON-RPC notification (no id) to stdout.
      def notify(method, params = {})
        write(Protocol.notification(method, params))
      end

      # Register a handler for a given JSON-RPC method.
      # The block receives (params, id) and must return a result hash.
      def on(method, &block)
        @handlers[method] = block
      end

      # Look up a handler instance by its short name (e.g. :prompt, :cancel).
      # Returns nil if the handler is not registered.
      def handler_instance(short_name)
        method_name = Handlers::SHORT_NAMES[short_name.to_sym]
        return nil unless method_name

        @handler_instances[method_name]
      end

      # Signal the server to stop its read loop.
      def stop!
        @running = false
      end

      private

      # ── Main loop ───────────────────────────────────────────────────

      def read_loop
        while @running
          line = $stdin.gets
          break if line.nil? # EOF — client disconnected

          line = line.strip
          next if line.empty?

          handle_line(line)
        end
      end

      def handle_line(line)
        msg = Protocol.parse(line)

        # Protocol.parse returns an error response hash when parsing fails.
        if msg.key?('error')
          write(msg)
          return
        end

        dispatch(msg)
      rescue StandardError => e
        warn "[IDE::Server] error handling message: #{e.message}"
        warn e.backtrace&.first(5)&.join("\n")

        id = msg.is_a?(Hash) ? msg['id'] : nil
        write(Protocol.error(id, Protocol::INTERNAL_ERROR, "Internal error: #{e.message}"))
      end

      # ── Dispatch ────────────────────────────────────────────────────

      def dispatch(msg)
        # Response messages from the extension (for our outbound requests via ide_client).
        # These have id + (result or error) but no method.
        if !msg.key?('method') && msg.key?('id') && (msg.key?('result') || msg.key?('error'))
          @ide_client.resolve(
            msg['id'],
            result: msg['result'],
            error: msg['error']
          )
          return
        end

        method = msg['method']
        params = msg['params'] || {}
        id     = msg['id']

        handler = @handlers[method]

        unless handler
          write(Protocol.error(id, Protocol::METHOD_NOT_FOUND, "Method not found: #{method}")) if id
          return
        end

        result = handler.call(params, id)

        # Only send a response for requests (those with an id).
        # Notifications (no id) do not get responses.
        write(Protocol.response(id, result)) if id
      end

      # ── Wire output ─────────────────────────────────────────────────

      def write(hash)
        serialized = Protocol.serialize(hash)
        @write_mutex.synchronize do
          $stdout.write(serialized)
          $stdout.flush
        end
      end

      # ── Signal handling ─────────────────────────────────────────────

      def setup_signal_traps!
        %w[TERM INT].each do |sig|
          trap(sig) do
            warn "[IDE::Server] received SIG#{sig}, shutting down"
            @running = false
          end
        end
      end

      # ── Shutdown ────────────────────────────────────────────────────

      def graceful_shutdown!
        warn '[IDE::Server] shutting down'
        save_session!
      end

      def save_session!
        # Delegate to Memory::SessionPersistence if available.
        @session_persistence.save if defined?(RubynCode::Memory::SessionPersistence) && @session_persistence
      rescue StandardError => e
        warn "[IDE::Server] session save failed: #{e.message}"
      end
    end
  end
end
