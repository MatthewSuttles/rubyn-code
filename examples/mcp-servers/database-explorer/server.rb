#!/usr/bin/env ruby
# frozen_string_literal: true

# MCP Server: Database Explorer
#
# A Model Context Protocol server that provides read-only access to SQLite databases.
# Exposes tools for listing tables, describing table schemas, and running SELECT queries.
#
# Usage:
#   DATABASE_PATH=db/development.sqlite3 ruby server.rb
#   ruby server.rb /path/to/database.sqlite3

require 'json'
require 'sqlite3'

module MCPServer
  module DatabaseExplorer
    SERVER_NAME = 'database-explorer'
    SERVER_VERSION = '1.0.0'

    TOOLS = [
      {
        name: 'list_tables',
        description: 'List all table names in the database',
        inputSchema: {
          type: 'object',
          properties: {},
          required: []
        }
      },
      {
        name: 'describe_table',
        description: 'Show columns, types, and indexes for a table',
        inputSchema: {
          type: 'object',
          properties: {
            table_name: {
              type: 'string',
              description: 'Name of the table to describe'
            }
          },
          required: ['table_name']
        }
      },
      {
        name: 'query',
        description: 'Run a read-only SQL query (SELECT only). Write operations are rejected.',
        inputSchema: {
          type: 'object',
          properties: {
            sql: {
              type: 'string',
              description: 'The SQL SELECT query to execute'
            }
          },
          required: ['sql']
        }
      }
    ].freeze

    WRITE_PATTERN = /\A\s*(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|REPLACE|MERGE|GRANT|REVOKE)/i

    class Server
      def initialize(database_path)
        @database_path = database_path
        @db = nil
      end

      def run
        connect_database!

        $stdin.each_line do |line|
          request = parse_request(line)
          next unless request

          response = handle_request(request)
          write_response(response) if response
        end
      ensure
        @db&.close
      end

      private

      def connect_database!
        unless File.exist?(@database_path)
          warn "Database not found: #{@database_path}"
          exit 1
        end

        @db = SQLite3::Database.new(@database_path, readonly: true)
        @db.results_as_hash = true
      end

      def parse_request(line)
        JSON.parse(line.strip)
      rescue JSON::ParserError
        nil
      end

      def write_response(response)
        $stdout.puts(JSON.generate(response))
        $stdout.flush
      end

      def handle_request(request)
        id = request['id']
        method = request['method']
        params = request['params'] || {}

        case method
        when 'initialize'       then handle_initialize(id)
        when 'tools/list'       then handle_tools_list(id)
        when 'tools/call'       then handle_tools_call(id, params)
        when 'notifications/initialized', 'notifications/cancelled'
          nil # Notifications have no response
        else
          error_response(id, -32_601, "Method not found: #{method}")
        end
      end

      def handle_initialize(id)
        {
          jsonrpc: '2.0',
          id: id,
          result: {
            protocolVersion: '2024-11-05',
            serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
            capabilities: { tools: {} }
          }
        }
      end

      def handle_tools_list(id)
        { jsonrpc: '2.0', id: id, result: { tools: TOOLS } }
      end

      def handle_tools_call(id, params)
        tool_name = params['name']
        arguments = params['arguments'] || {}

        result = case tool_name
                 when 'list_tables'    then call_list_tables
                 when 'describe_table' then call_describe_table(arguments)
                 when 'query'          then call_query(arguments)
                 else
                   return error_response(id, -32_602, "Unknown tool: #{tool_name}")
                 end

        { jsonrpc: '2.0', id: id, result: { content: [{ type: 'text', text: result }] } }
      rescue SQLite3::Exception => e
        error_text = "SQL error: #{e.message}"
        { jsonrpc: '2.0', id: id, result: { content: [{ type: 'text', text: error_text }], isError: true } }
      end

      def call_list_tables
        rows = @db.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        tables = rows.map { |r| r['name'] }
        JSON.pretty_generate(tables: tables, count: tables.size)
      end

      def call_describe_table(arguments)
        table_name = arguments['table_name']
        return 'Error: table_name is required' unless table_name

        sanitized = table_name.gsub(/[^a-zA-Z0-9_]/, '')
        columns = @db.execute("PRAGMA table_info(#{sanitized})")
        indexes = @db.execute("PRAGMA index_list(#{sanitized})")

        index_details = indexes.map do |idx|
          cols = @db.execute("PRAGMA index_info(#{idx['name']})")
          {
            name: idx['name'],
            unique: idx['unique'] == 1,
            columns: cols.map { |c| c['name'] }
          }
        end

        JSON.pretty_generate(
          table: sanitized,
          columns: columns.map do |c|
            { name: c['name'], type: c['type'], nullable: c['notnull'].zero?, default: c['dflt_value'],
              primary_key: c['pk'] == 1 }
          end,
          indexes: index_details
        )
      end

      def call_query(arguments)
        sql = arguments['sql']
        return 'Error: sql is required' unless sql

        if WRITE_PATTERN.match?(sql)
          return 'Error: only SELECT queries are allowed. Write operations (INSERT, UPDATE, DELETE, etc.) are rejected.'
        end

        rows = @db.execute(sql)
        JSON.pretty_generate(rows: rows, count: rows.size)
      end

      def error_response(id, code, message)
        { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
      end
    end
  end
end

# Resolve database path from argument or environment variable
database_path = ARGV[0] || ENV.fetch('DATABASE_PATH', nil)

unless database_path
  warn 'Usage: DATABASE_PATH=path/to/db.sqlite3 ruby server.rb'
  warn '   or: ruby server.rb path/to/db.sqlite3'
  exit 1
end

MCPServer::DatabaseExplorer::Server.new(database_path).run
