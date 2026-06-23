# frozen_string_literal: true

module RubynCode
  module MCP
    # Bridges an MCP server's *resources* and *prompts* into native RubynCode
    # tools — the non-"tools" half of the MCP surface. Split out of ToolBridge
    # so tool bridging and resource/prompt bridging each stay one focused job.
    #
    # Each capability registers a single tool whose description lists what's
    # available (resource URIs / prompt names) and reads or fetches any of them.
    module ServerExtrasBridge
      class << self
        # If the server exposes resources, register one tool that lists the
        # available URIs (in its description) and reads any of them.
        #
        # @return [Array<Class>] the [read_resource] tool class, or [] if none
        def bridge_resources(mcp_client)
          resources = safe_list(mcp_client, :resources)
          return [] if resources.empty?

          klass = create_resource_tool(mcp_client, resources)
          Tools::Registry.register(klass)
          [klass]
        end

        # If the server exposes prompts, register one tool that lists the
        # available prompt names and fetches any of them (with arguments).
        #
        # @return [Array<Class>] the [get_prompt] tool class, or [] if none
        def bridge_prompts(mcp_client)
          prompts = safe_list(mcp_client, :prompts)
          return [] if prompts.empty?

          klass = create_prompt_tool(mcp_client, prompts)
          Tools::Registry.register(klass)
          [klass]
        end

        private

        def safe_list(mcp_client, method)
          Array(mcp_client.public_send(method))
        rescue StandardError
          []
        end

        def create_resource_tool(mcp_client, resources)
          listing = resources.map { |r| "- #{r['uri']}#{r['name'] && " (#{r['name']})"}" }.join("\n")
          description = "Read a resource from MCP server '#{mcp_client.name}'. Available resources:\n#{listing}"
          params = { uri: { type: :string, description: 'The resource URI to read', required: true } }

          tool_name = "mcp_#{ToolBridge.sanitize_name(mcp_client.name)}_read_resource"
          build_dynamic_tool(tool_name, description, params) do |args|
            format_resource_contents(mcp_client.read_resource(args[:uri] || args['uri']))
          end
        end

        def create_prompt_tool(mcp_client, prompts)
          listing = prompts.map { |p| "- #{p['name']}#{p['description'] && ": #{p['description']}"}" }.join("\n")
          description = "Fetch a prompt from MCP server '#{mcp_client.name}'. Available prompts:\n#{listing}"
          params = {
            name: { type: :string, description: 'The prompt name', required: true },
            arguments: { type: :object, description: 'Prompt arguments (optional)', required: false }
          }

          tool_name = "mcp_#{ToolBridge.sanitize_name(mcp_client.name)}_get_prompt"
          build_dynamic_tool(tool_name, description, params) do |args|
            result = mcp_client.get_prompt(args[:name] || args['name'], args[:arguments] || args['arguments'] || {})
            format_prompt_messages(result)
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
      end
    end
  end
end
