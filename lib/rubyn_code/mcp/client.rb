# frozen_string_literal: true

require 'json'

module RubynCode
  module MCP
    # High-level MCP client that manages the connection lifecycle,
    # tool discovery, and tool invocation for a single MCP server.
    class Client
      INITIALIZE_TIMEOUT = 10

      class ClientError < RubynCode::Error
      end

      attr_reader :name, :transport

      # @param name [String] human-readable name for this MCP server connection
      # @param transport [StdioTransport, SSETransport] the underlying transport
      def initialize(name:, transport:)
        @name = name
        @transport = transport
        @tools_cache = nil
        @initialized = false
      end

      # Starts the transport, performs the MCP initialize handshake,
      # and discovers available tools.
      #
      # @return [void]
      # @raise [ClientError] if initialization fails
      def connect!
        @transport.start!
        perform_initialize
        @initialized = true
      rescue StandardError => e
        @transport.stop!
        raise ClientError, "Failed to connect to MCP server '#{@name}': #{e.message}"
      end

      # Returns the list of tool definitions from the MCP server.
      # Each tool is a Hash with "name", "description", and "inputSchema" keys.
      #
      # @return [Array<Hash>] tool definitions in JSON Schema format
      def tools
        @tools ||= discover_tools
      end

      # Invokes a tool on the MCP server.
      #
      # @param tool_name [String] the name of the tool to call
      # @param arguments [Hash] the arguments to pass to the tool
      # @return [Hash] the tool's result
      # @raise [ClientError] if the client is not connected
      def call_tool(tool_name, arguments = {})
        ensure_connected!

        @transport.send_request('tools/call', {
                                  name: tool_name,
                                  arguments: arguments
                                })
      end

      # Returns the resources advertised by the server (empty unless the
      # server declared the `resources` capability). Each entry is a Hash with
      # "uri", "name", and optionally "description"/"mimeType".
      #
      # @return [Array<Hash>]
      def resources
        return [] unless supports_resources?

        @resources ||= @transport.send_request('resources/list')&.fetch('resources', []) || []
      rescue StandardError => e
        RubynCode::Debug.warn("MCP '#{@name}' resources/list failed: #{e.message}")
        []
      end

      # Reads a single resource by URI.
      #
      # @param uri [String]
      # @return [Hash] result with a "contents" array
      def read_resource(uri)
        ensure_connected!
        @transport.send_request('resources/read', { uri: uri })
      end

      # Returns the prompts advertised by the server (empty unless the server
      # declared the `prompts` capability). Each entry has "name" and
      # optionally "description"/"arguments".
      #
      # @return [Array<Hash>]
      def prompts
        return [] unless supports_prompts?

        @prompts ||= @transport.send_request('prompts/list')&.fetch('prompts', []) || []
      rescue StandardError => e
        RubynCode::Debug.warn("MCP '#{@name}' prompts/list failed: #{e.message}")
        []
      end

      # Fetches a prompt, expanding its template with the given arguments.
      #
      # @param name [String]
      # @param arguments [Hash]
      # @return [Hash] result with "messages" (and optionally "description")
      def get_prompt(name, arguments = {})
        ensure_connected!
        @transport.send_request('prompts/get', { name: name, arguments: arguments })
      end

      # @return [Boolean] whether the server advertised the resources capability
      def supports_resources?
        @server_capabilities.is_a?(Hash) && @server_capabilities.key?('resources')
      end

      # @return [Boolean] whether the server advertised the prompts capability
      def supports_prompts?
        @server_capabilities.is_a?(Hash) && @server_capabilities.key?('prompts')
      end

      # Gracefully disconnects from the MCP server.
      #
      # @return [void]
      def disconnect!
        @transport.stop!
        @initialized = false
        @tools = nil
        @resources = nil
        @prompts = nil
      end

      # Returns whether the client is connected and the transport is alive.
      #
      # @return [Boolean]
      def connected?
        @initialized && @transport.alive?
      end

      class << self
        # Factory method that creates a Client with the appropriate transport
        # based on the server configuration.
        #
        # Configs with a :url key use SSETransport; all others use StdioTransport.
        #
        # @param server_config [Hash] configuration hash with :name, :command/:url, :args, :env
        # @return [Client]
        def from_config(server_config)
          name = server_config[:name]

          transport = if server_config[:url]
                        SSETransport.new(
                          url: server_config[:url],
                          timeout: server_config[:timeout] || SSETransport::DEFAULT_TIMEOUT
                        )
                      else
                        StdioTransport.new(
                          command: server_config[:command],
                          args: server_config[:args] || [],
                          env: server_config[:env] || {},
                          timeout: server_config[:timeout] || StdioTransport::DEFAULT_TIMEOUT
                        )
                      end

          new(name: name, transport: transport)
        end
      end

      private

      def perform_initialize
        result = @transport.send_request('initialize', {
                                           protocolVersion: '2024-11-05',
                                           capabilities: {
                                             tools: {}
                                           },
                                           clientInfo: {
                                             name: 'rubyn-code',
                                             version: RubynCode::VERSION
                                           }
                                         })

        @server_info = result&.dig('serverInfo')
        @server_capabilities = result&.dig('capabilities')

        @transport.send_notification('notifications/initialized') if @transport.respond_to?(:send_notification)
      end

      def discover_tools
        ensure_connected!

        result = @transport.send_request('tools/list')
        result&.fetch('tools', []) || []
      end

      def ensure_connected!
        raise ClientError, "Client '#{@name}' is not connected. Call #connect! first." unless @initialized
      end
    end
  end
end
