# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Mcp < Base
        def self.command_name = '/mcp'
        def self.description = 'MCP server status'

        def execute(_args, ctx)
          configs = load_configs(ctx.project_root)

          if configs.empty?
            ctx.renderer.info('No MCP servers configured.')
            puts '  Add servers to .rubyn-code/mcp.json — see docs/MCP.md for details.'
            return
          end

          ctx.renderer.info("MCP servers (#{configs.size}):")
          puts

          configs.each { |cfg| render_server(cfg) }
        end

        private

        def load_configs(project_root)
          MCP::Config.load(project_root)
        end

        def render_server(cfg)
          client = build_client(cfg)
          status, counts = probe_server(client)
          icon = status_icon(status)

          puts "  #{icon} #{cfg[:name]} [#{status}]#{capability_label(counts)}"
          render_transport_info(cfg)
        ensure
          client&.disconnect! if client&.connected?
        end

        def capability_label(counts)
          return '' unless counts

          parts = []
          parts << "#{counts[:tools]} tools"
          parts << "#{counts[:resources]} resources" if counts[:resources].positive?
          parts << "#{counts[:prompts]} prompts" if counts[:prompts].positive?
          " (#{parts.join(', ')})"
        end

        def build_client(cfg)
          MCP::Client.from_config(cfg)
        end

        def probe_server(client)
          client.connect!
          counts = {
            tools: client.tools.size,
            resources: client.resources.size,
            prompts: client.prompts.size
          }
          [:connected, counts]
        rescue StandardError
          [:error, nil]
        end

        def render_transport_info(cfg)
          if cfg[:url]
            puts "    transport: SSE  url: #{cfg[:url]}"
          else
            puts "    transport: stdio  command: #{cfg[:command]} #{cfg[:args].join(' ')}".rstrip
          end
        end

        def status_icon(status)
          case status
          when :connected then green('*')
          when :error     then red('x')
          else yellow('?')
          end
        end

        def green(text)  = "\e[32m#{text}\e[0m"
        def red(text)    = "\e[31m#{text}\e[0m"
        def yellow(text) = "\e[33m#{text}\e[0m"
      end
    end
  end
end
