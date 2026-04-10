#!/usr/bin/env ruby
# frozen_string_literal: true

# MCP Server: RubyGems Lookup
#
# A Model Context Protocol server that queries the RubyGems.org API.
# Exposes tools for searching gems, fetching gem info, and listing version history.
#
# Usage:
#   ruby server.rb
#
# Zero external dependencies — uses only Ruby stdlib.

require 'json'
require 'net/http'
require 'uri'

module MCPServer
  module RubyGemsLookup
    SERVER_NAME = 'rubygems-lookup'
    SERVER_VERSION = '1.0.0'
    API_BASE = 'https://rubygems.org/api/v1'

    TOOLS = [
      {
        name: 'search_gems',
        description: 'Search RubyGems.org for gems matching a query. ' \
                     'Returns the top results with name, version, and description.',
        inputSchema: {
          type: 'object',
          properties: {
            query: {
              type: 'string',
              description: 'Search query (gem name or keyword)'
            }
          },
          required: ['query']
        }
      },
      {
        name: 'gem_info',
        description: 'Get detailed information about a specific gem: ' \
                     'version, description, homepage, dependencies, and more.',
        inputSchema: {
          type: 'object',
          properties: {
            name: {
              type: 'string',
              description: 'Exact gem name (e.g. "rails", "sidekiq")'
            }
          },
          required: ['name']
        }
      },
      {
        name: 'gem_versions',
        description: 'List recent version history for a gem, including version numbers, release dates, and platforms.',
        inputSchema: {
          type: 'object',
          properties: {
            name: {
              type: 'string',
              description: 'Exact gem name'
            }
          },
          required: ['name']
        }
      }
    ].freeze

    class Server
      def run
        $stdin.each_line do |line|
          request = parse_request(line)
          next unless request

          response = handle_request(request)
          write_response(response) if response
        end
      end

      private

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
          nil
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
                 when 'search_gems'  then call_search_gems(arguments)
                 when 'gem_info'     then call_gem_info(arguments)
                 when 'gem_versions' then call_gem_versions(arguments)
                 else
                   return error_response(id, -32_602, "Unknown tool: #{tool_name}")
                 end

        { jsonrpc: '2.0', id: id, result: { content: [{ type: 'text', text: result }] } }
      rescue StandardError => e
        error_text = "API error: #{e.message}"
        { jsonrpc: '2.0', id: id, result: { content: [{ type: 'text', text: error_text }], isError: true } }
      end

      def call_search_gems(arguments)
        query = arguments['query']
        return 'Error: query is required' unless query

        data = api_get("/search.json?query=#{URI.encode_www_form_component(query)}")
        gems = data.first(10).map do |gem|
          {
            name: gem['name'],
            version: gem['version'],
            downloads: gem['downloads'],
            info: gem['info']&.slice(0, 200)
          }
        end

        JSON.pretty_generate(results: gems, count: gems.size)
      end

      def call_gem_info(arguments)
        name = arguments['name']
        return 'Error: name is required' unless name

        gem = api_get("/gems/#{URI.encode_www_form_component(name)}.json")

        JSON.pretty_generate(
          name: gem['name'],
          version: gem['version'],
          authors: gem['authors'],
          info: gem['info'],
          homepage_uri: gem['homepage_uri'],
          source_code_uri: gem['source_code_uri'],
          documentation_uri: gem['documentation_uri'],
          licenses: gem['licenses'],
          downloads: gem['downloads'],
          dependencies: {
            runtime: extract_deps(gem, 'runtime'),
            development: extract_deps(gem, 'development')
          }
        )
      end

      def call_gem_versions(arguments)
        name = arguments['name']
        return 'Error: name is required' unless name

        data = api_get("/versions/#{URI.encode_www_form_component(name)}.json")
        versions = data.first(20).map do |v|
          {
            number: v['number'],
            platform: v['platform'],
            created_at: v['created_at'],
            prerelease: v['prerelease'],
            downloads_count: v['downloads_count']
          }
        end

        JSON.pretty_generate(gem: name, versions: versions, count: versions.size)
      end

      def extract_deps(gem, type)
        deps = gem.dig('dependencies', type) || []
        deps.map { |d| { name: d['name'], requirements: d['requirements'] } }
      end

      def api_get(path)
        uri = URI("#{API_BASE}#{path}")
        response = Net::HTTP.get_response(uri)

        unless response.is_a?(Net::HTTPSuccess)
          raise "RubyGems API returned #{response.code}: #{response.body&.slice(0, 200)}"
        end

        JSON.parse(response.body)
      end

      def error_response(id, code, message)
        { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
      end
    end
  end
end

MCPServer::RubyGemsLookup::Server.new.run
