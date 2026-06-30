# frozen_string_literal: true

require 'json'
require 'rubyn_code/mcp/config'

module RubynCode
  module MCP
    # Discovers MCP server definitions from a project's `.mcp.json` file
    # (the Claude Code–style layout at the project root) and merges them
    # with the user-level `.rubyn-code/mcp.json` definitions parsed by
    # `MCP::Config`.
    #
    # Project-level entries are tagged `source: :project` so /mcp can
    # distinguish them from user-level entries.
    module Discovery
      PROJECT_CONFIG_FILENAME = '.mcp.json'

      Entry = Data.define(:name, :command, :args, :env, :url, :source)

      module_function

      # @param project_root [String, nil] project root (nil => nothing discovered)
      # @return [Array<Entry>]
      def discover(project_root)
        user  = MCP::Config.load(project_root.to_s).map { |cfg| to_entry(cfg, :user) }
        proj  = load_project(project_root)
        user + proj
      end

      # @param project_root [String, nil]
      # @return [Array<Entry>]
      def load_project(project_root)
        return [] if project_root.to_s.empty?

        path = File.join(project_root, PROJECT_CONFIG_FILENAME)
        return [] unless File.exist?(path)

        data = JSON.parse(File.read(path))
        Array(data['mcpServers']).filter_map do |name, server_def|
          build_entry(name, server_def, :project)
        end
      rescue JSON::ParserError => e
        RubynCode::Debug.warn("[MCP::Discovery] Failed to parse #{path}: #{e.message}")
        []
      rescue SystemCallError => e
        RubynCode::Debug.warn("[MCP::Discovery] Could not read #{path}: #{e.message}")
        []
      end

      # @return [Array<Entry>] entries that the local runner can start right now
      def stdio_servers(entries)
        entries.reject { |e| e.command.to_s.empty? }
      end

      # @return [Array<Entry>] entries that need a network protocol (deferred)
      def remote_servers(entries)
        entries.select { |e| e.command.to_s.empty? && !e.url.to_s.empty? }
      end

      def to_entry(cfg, source)
        Entry.new(
          name: cfg[:name],
          command: cfg[:command],
          args: cfg[:args],
          env: cfg[:env],
          url: cfg[:url],
          source: source
        )
      end

      def build_entry(name, server_def, source)
        return nil unless server_def.is_a?(Hash)

        command = server_def['command'].to_s
        url     = server_def['url'].to_s

        if command.empty? && url.empty?
          RubynCode::Debug.warn("[MCP::Discovery] Skipping #{name}: no command or url")
          return nil
        end

        Entry.new(
          name: name,
          command: command,
          args: Array(server_def['args']),
          env: server_def['env'].is_a?(Hash) ? server_def['env'].transform_keys(&:to_s) : {},
          url: url,
          source: source
        )
      end
    end
  end
end
