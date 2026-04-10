# frozen_string_literal: true

require 'json'

module RubynCode
  module MCP
    # Parses MCP server configuration from .rubyn-code/mcp.json in the project directory.
    #
    # Expected JSON format:
    #   {
    #     "mcpServers": {
    #       "server-name": {
    #         "command": "npx",
    #         "args": ["-y", "@modelcontextprotocol/server-github"],
    #         "env": { "GITHUB_TOKEN": "${GITHUB_TOKEN}" }
    #       }
    #     }
    #   }
    module Config
      CONFIG_FILENAME = '.rubyn-code/mcp.json'

      ENV_VAR_PATTERN = /\$\{([^}]+)\}/

      class << self
        # Reads and parses the MCP server configuration for a project.
        #
        # @param project_path [String] root directory of the project
        # @return [Array<Hash>] array of server configs with keys :name, :command, :args, :env
        def load(project_path)
          config_path = File.join(project_path, CONFIG_FILENAME)
          return [] unless File.exist?(config_path)

          data = JSON.parse(File.read(config_path))
          parse_servers(data['mcpServers'] || {})
        rescue JSON::ParserError => e
          warn "[MCP::Config] Failed to parse #{config_path}: #{e.message}"
          []
        rescue SystemCallError => e
          warn "[MCP::Config] Could not read #{config_path}: #{e.message}"
          []
        end

        private

        # Expands environment variable references (${VAR_NAME}) in config values.
        #
        # @param env_hash [Hash<String, String>] raw env key-value pairs
        # @return [Hash<String, String>] expanded env key-value pairs
        def parse_servers(servers)
          servers.map do |name, server_def|
            { name: name, command: server_def['command'],
              args: Array(server_def['args']), env: expand_env(server_def['env'] || {}),
              url: server_def['url'], timeout: server_def['timeout'] }
          end
        end

        def expand_env(env_hash)
          env_hash.each_with_object({}) do |(key, value), result|
            result[key] = expand_value(value)
          end
        end

        # Replaces ${VAR} patterns with actual environment variable values.
        #
        # @param value [String] a string potentially containing ${VAR} references
        # @return [String] the string with env vars expanded
        def expand_value(value)
          return value unless value.is_a?(String)

          value.gsub(ENV_VAR_PATTERN) do
            env_name = ::Regexp.last_match(1)
            ENV.fetch(env_name) do
              warn "[MCP::Config] Environment variable #{env_name} is not set"
              ''
            end
          end
        end
      end
    end
  end
end
