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
      class << self
        # Discovers tools from an MCP client and creates corresponding
        # RubynCode tool classes.
        #
        # @param mcp_client [MCP::Client] a connected MCP client
        # @return [Array<Class>] the dynamically created tool classes
        def bridge(mcp_client)
          tools = mcp_client.tools
          return [] if tools.nil? || tools.empty?

          tools.map do |tool_def|
            build_tool_class(mcp_client, tool_def)
          end
        end

        private

        # Builds a single tool class for an MCP tool definition.
        #
        # @param mcp_client [MCP::Client] the MCP client to delegate to
        # @param tool_def [Hash] tool definition with "name", "description", "inputSchema"
        # @return [Class] the newly created and registered tool class
        def build_tool_class(mcp_client, tool_def)
          remote_name = tool_def['name']
          tool_name = "mcp_#{sanitize_name(remote_name)}"
          description = tool_def['description'] || "MCP tool: #{remote_name}"
          input_schema = tool_def['inputSchema'] || {}
          parameters = build_parameters_from_schema(input_schema)

          klass = Class.new(Tools::Base) do
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
                if result.key?('content')
                  extract_content(result['content'])
                else
                  JSON.generate(result)
                end
              when String
                result
              else
                result.to_s
              end
            end

            define_method(:extract_content) do |content|
              Array(content).map do |block|
                case block['type']
                when 'text'
                  block['text']
                when 'image'
                  "[image: #{block['mimeType']}]"
                when 'resource'
                  block.dig('resource', 'text') || "[resource: #{block.dig('resource', 'uri')}]"
                else
                  block.to_s
                end
              end.join("\n")
            end
          end

          # Build parameter definitions from JSON Schema
          klass.define_singleton_method(:build_parameters) do |schema|
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

          klass.define_singleton_method(:map_json_type) do |json_type|
            case json_type
            when 'string'  then :string
            when 'integer' then :integer
            when 'number'  then :number
            when 'boolean' then :boolean
            when 'array'   then :array
            when 'object'  then :object
            else :string
            end
          end

          Tools::Registry.register(klass)
          klass
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
          case json_type
          when 'string'  then :string
          when 'integer' then :integer
          when 'number'  then :number
          when 'boolean' then :boolean
          when 'array'   then :array
          when 'object'  then :object
          else :string
          end
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
