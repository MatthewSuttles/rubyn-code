# frozen_string_literal: true

module RubynCode
  module MCP
    # Wraps MCP tools as native RubynCode tools by dynamically creating
    # tool classes that delegate execution to the MCP client.
    #
    # Each bridged tool:
    # - Has TOOL_NAME prefixed with "mcp_"
    # - Has RISK_LEVEL = :external
    # - Delegates #execute to the MCP client's #call_tool
    # - Registers itself with Tools::Registry
    module ToolBridge
      JSON_TYPE_MAP = {
        'string' => :string, 'integer' => :integer, 'number' => :number,
        'boolean' => :boolean, 'array' => :array, 'object' => :object
      }.freeze

      class << self
        # Discovers tools from an MCP client and creates corresponding
        # RubynCode tool classes.
        #
        # @param mcp_client [MCP::Client] a connected MCP client
        # @return [Array<Class>] the dynamically created tool classes
        def bridge(mcp_client)
          classes = Array(mcp_client.tools).map { |tool_def| build_tool_class(mcp_client, tool_def) }
          classes.concat(bridge_resources(mcp_client))
          classes.concat(bridge_prompts(mcp_client))
          classes
        end

        private

        # If the server exposes resources, register one tool that lists the
        # available URIs (in its description) and reads any of them.
        def bridge_resources(mcp_client)
          resources = safe_list(mcp_client, :resources)
          return [] if resources.empty?

          klass = create_resource_tool(mcp_client, resources)
          Tools::Registry.register(klass)
          [klass]
        end

        # If the server exposes prompts, register one tool that lists the
        # available prompt names and fetches any of them (with arguments).
        def bridge_prompts(mcp_client)
          prompts = safe_list(mcp_client, :prompts)
          return [] if prompts.empty?

          klass = create_prompt_tool(mcp_client, prompts)
          Tools::Registry.register(klass)
          [klass]
        end

        def safe_list(mcp_client, method)
          Array(mcp_client.public_send(method))
        rescue StandardError
          []
        end

        def create_resource_tool(mcp_client, resources)
          listing = resources.map { |r| "- #{r['uri']}#{r['name'] && " (#{r['name']})"}" }.join("\n")
          description = "Read a resource from MCP server '#{mcp_client.name}'. Available resources:\n#{listing}"
          params = { uri: { type: :string, description: 'The resource URI to read', required: true } }

          build_dynamic_tool("mcp_#{sanitize_name(mcp_client.name)}_read_resource", description, params) do |args|
            result = mcp_client.read_resource(args[:uri] || args['uri'])
            ToolBridge.send(:format_resource_contents, result)
          end
        end

        def create_prompt_tool(mcp_client, prompts)
          listing = prompts.map { |p| "- #{p['name']}#{p['description'] && ": #{p['description']}"}" }.join("\n")
          description = "Fetch a prompt from MCP server '#{mcp_client.name}'. Available prompts:\n#{listing}"
          params = {
            name: { type: :string, description: 'The prompt name', required: true },
            arguments: { type: :object, description: 'Prompt arguments (optional)', required: false }
          }

          build_dynamic_tool("mcp_#{sanitize_name(mcp_client.name)}_get_prompt", description, params) do |args|
            result = mcp_client.get_prompt(args[:name] || args['name'], args[:arguments] || args['arguments'] || {})
            ToolBridge.send(:format_prompt_messages, result)
          end
        end

        # Build a Tools::Base subclass whose #execute delegates to the block.
        def build_dynamic_tool(tool_name, description, parameters, &handler)
          Class.new(Tools::Base) do
            const_set(:TOOL_NAME, tool_name)
            const_set(:DESCRIPTION, description)
            const_set(:PARAMETERS, parameters)
            const_set(:RISK_LEVEL, :external)
            const_set(:REQUIRES_CONFIRMATION, true)

            define_method(:execute) { |**params| handler.call(params) }
          end
        end

        def format_resource_contents(result)
          contents = result.is_a?(Hash) ? Array(result['contents']) : []
          return result.to_s if contents.empty?

          contents.map { |c| c['text'] || "[binary resource: #{c['uri']} #{c['mimeType']}]" }.join("\n")
        end

        def format_prompt_messages(result)
          messages = result.is_a?(Hash) ? Array(result['messages']) : []
          return result.to_s if messages.empty?

          messages.map { |m| "#{m['role']}: #{prompt_message_text(m['content'])}" }.join("\n\n")
        end

        def prompt_message_text(content)
          case content
          when Hash then content['text'] || content.to_s
          when Array then content.map { |b| b.is_a?(Hash) ? b['text'] : b }.compact.join("\n")
          else content.to_s
          end
        end

        # Builds a single tool class for an MCP tool definition.
        #
        # @param mcp_client [MCP::Client] the MCP client to delegate to
        # @param tool_def [Hash] tool definition with "name", "description", "inputSchema"
        # @return [Class] the newly created and registered tool class
        def build_tool_class(mcp_client, tool_def)
          remote_name = tool_def['name']
          attrs = {
            tool_name: "mcp_#{sanitize_name(remote_name)}",
            description: tool_def['description'] || "MCP tool: #{remote_name}",
            parameters: build_parameters_from_schema(tool_def['inputSchema'] || {})
          }
          klass = create_tool_class(attrs[:tool_name], attrs[:description], attrs[:parameters], mcp_client,
                                    remote_name)
          Tools::Registry.register(klass)
          klass
        end

        def create_tool_class(tool_name, description, parameters, mcp_client, remote_name) # rubocop:disable Metrics/MethodLength -- dynamic class creation requires setting many constants
          bridge = self

          Class.new(Tools::Base) do
            const_set(:TOOL_NAME, tool_name)
            const_set(:DESCRIPTION, description)
            const_set(:PARAMETERS, parameters)
            const_set(:RISK_LEVEL, :external)
            const_set(:REQUIRES_CONFIRMATION, true)

            define_method(:mcp_client) { mcp_client }
            define_method(:remote_tool_name) { remote_name }

            def execute(**params)
              result = mcp_client.call_tool(remote_tool_name, params)
              format_result(result)
            end

            private

            define_method(:format_result) do |result|
              case result
              when Hash
                result.key?('content') ? extract_content(result['content']) : JSON.generate(result)
              when String then result
              else result.to_s
              end
            end

            define_method(:extract_content) do |content|
              Array(content).map { |block| bridge.send(:format_mcp_block, block) }.join("\n")
            end
          end
        end

        def format_mcp_block(block)
          case block['type']
          when 'text'     then block['text']
          when 'image'    then "[image: #{block['mimeType']}]"
          when 'resource' then block.dig('resource', 'text') || "[resource: #{block.dig('resource', 'uri')}]"
          else block.to_s
          end
        end

        # Builds parameter definitions from a JSON Schema.
        #
        # @param schema [Hash] JSON Schema with "properties" and "required"
        # @return [Hash]
        def build_parameters_from_schema(schema)
          properties = schema['properties'] || {}
          required = schema['required'] || []

          properties.each_with_object({}) do |(name, prop), params|
            params[name.to_sym] = {
              type: map_json_type(prop['type']),
              description: prop['description'] || '',
              required: required.include?(name)
            }
          end
        end

        # Maps a JSON Schema type string to a Ruby symbol.
        #
        # @param json_type [String]
        # @return [Symbol]
        def map_json_type(json_type)
          JSON_TYPE_MAP.fetch(json_type, :string)
        end

        # Sanitizes a tool name for use as a Ruby-friendly identifier.
        #
        # @param name [String] the original tool name
        # @return [String] sanitized name
        def sanitize_name(name)
          name.to_s.gsub(/[^a-zA-Z0-9_]/, '_').gsub(/_+/, '_').downcase
        end
      end
    end
  end
end
