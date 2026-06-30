# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class Mcp < Base
        def self.command_name = '/mcp'
        def self.description = 'MCP server status'

        def execute(_args, ctx)
          entries = load_entries(ctx.project_root)

          if entries.empty?
            ctx.renderer.info('No MCP servers configured.')
            puts '  Add servers to .rubyn-code/mcp.json — see docs/MCP.md for details.'
            return
          end

          ctx.renderer.info("MCP servers (#{entries.size}):")
          puts

          entries.each { |entry| render_server(entry) }
        end

        private

        # Load merged user + project entries via MCP::Discovery so the
        # output can show which servers came from `~/.rubyn-code/mcp.json`
        # vs the project-root `.mcp.json`.
        def load_entries(project_root)
          MCP::Discovery.discover(project_root)
        end

        def source_label(source)
          case source
          when :project then '[project]'
          when :user    then '[user]'
          else               '[-]'
          end
        end

        def render_server(entry)
          cfg = entry_to_config(entry)
          client = build_client(cfg)
          status, counts = probe_server(client)
          icon = status_icon(status)
          label = source_label(entry.respond_to?(:source) ? entry.source : :user)

          puts "  #{icon} #{entry.name} #{label} [#{status}]#{capability_label(counts)}"
          render_transport_info(cfg)
        ensure
          client&.disconnect! if client&.connected?
        end

        # Discovery::Entry → Config hash shape so existing renderers work.
        def entry_to_config(entry)
          {
            name: entry.name,
            command: entry.command,
            args: entry.args,
            env: entry.env,
            url: entry.url
          }
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
