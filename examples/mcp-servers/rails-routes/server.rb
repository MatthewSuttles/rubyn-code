#!/usr/bin/env ruby
# frozen_string_literal: true

# MCP Server: Rails Routes
#
# A Model Context Protocol server that exposes Rails route information.
# Parses the output of `rails routes` or falls back to reading config/routes.rb.
#
# Usage:
#   ruby server.rb                          # auto-detects Rails project in cwd
#   RAILS_ROOT=/path/to/app ruby server.rb  # specify project path

require 'json'

module MCPServer
  module RailsRoutes
    SERVER_NAME = 'rails-routes'
    SERVER_VERSION = '1.0.0'

    TOOLS = [
      {
        name: 'list_routes',
        description: 'List all routes in the Rails application (method, path, controller#action).',
        inputSchema: {
          type: 'object',
          properties: {},
          required: []
        }
      },
      {
        name: 'routes_for_controller',
        description: 'Filter routes by controller name. Returns all routes handled by the specified controller.',
        inputSchema: {
          type: 'object',
          properties: {
            controller: {
              type: 'string',
              description: 'Controller name to filter by (e.g. "users", "api/v1/posts")'
            }
          },
          required: ['controller']
        }
      },
      {
        name: 'find_route',
        description: 'Find which controller#action handles a given URL path.',
        inputSchema: {
          type: 'object',
          properties: {
            path: {
              type: 'string',
              description: 'URL path to look up (e.g. "/users/123", "/api/v1/posts")'
            }
          },
          required: ['path']
        }
      }
    ].freeze

    Route = Data.define(:verb, :path, :controller_action, :name)

    class Server
      def initialize(rails_root)
        @rails_root = rails_root
        @routes = nil
      end

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
                 when 'list_routes'           then call_list_routes
                 when 'routes_for_controller' then call_routes_for_controller(arguments)
                 when 'find_route'            then call_find_route(arguments)
                 else
                   return error_response(id, -32_602, "Unknown tool: #{tool_name}")
                 end

        { jsonrpc: '2.0', id: id, result: { content: [{ type: 'text', text: result }] } }
      rescue StandardError => e
        error_text = "Error: #{e.message}"
        { jsonrpc: '2.0', id: id, result: { content: [{ type: 'text', text: error_text }], isError: true } }
      end

      def call_list_routes
        routes = load_routes
        formatted = routes.map { |r| format_route(r) }
        JSON.pretty_generate(routes: formatted, count: formatted.size)
      end

      def call_routes_for_controller(arguments)
        controller = arguments['controller']
        return 'Error: controller is required' unless controller

        routes = load_routes
        matches = routes.select { |r| r.controller_action&.start_with?("#{controller}#") }
        formatted = matches.map { |r| format_route(r) }
        JSON.pretty_generate(controller: controller, routes: formatted, count: formatted.size)
      end

      def call_find_route(arguments)
        path = arguments['path']
        return 'Error: path is required' unless path

        routes = load_routes
        matches = routes.select { |r| route_matches_path?(r, path) }
        formatted = matches.map { |r| format_route(r) }

        if formatted.empty?
          JSON.pretty_generate(path: path, message: 'No matching route found', routes: [])
        else
          JSON.pretty_generate(path: path, routes: formatted, count: formatted.size)
        end
      end

      def load_routes
        @load_routes ||= parse_rails_routes || parse_routes_file || []
      end

      def parse_rails_routes
        bin = File.exist?(File.join(@rails_root, 'bin', 'rails')) ? 'bin/rails' : 'rails'
        output = `cd #{@rails_root} && #{bin} routes 2>/dev/null`
        return nil unless $?.success? && !output.strip.empty? # rubocop:disable Style/SpecialGlobalVars
        # Verify the output looks like actual route table output
        # Real rails routes output has lines with controller#action patterns like "users#index"
        return nil unless output.match?(/\w+#\w+/)

        parse_routes_output(output)
      end

      def parse_routes_output(output) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
        routes = []
        output.each_line do |line|
          line = line.strip
          next if line.empty? || line.start_with?('--')
          next if line.include?('Prefix') && line.include?('Verb') # header line

          parts = line.split(/\s{2,}/)
          next if parts.size < 3
          # Skip lines that don't look like routes (must have a /path and a controller#action)
          next unless parts.any? { |p| p.start_with?('/') } && parts.any? { |p| p.match?(/\A\w+#\w+/) }

          # Routes output format: [prefix] verb uri_pattern controller#action
          if parts.size >= 4
            routes << Route.new(verb: parts[1], path: parts[2], controller_action: parts[3], name: parts[0])
          elsif parts.size == 3
            routes << Route.new(verb: parts[0], path: parts[1], controller_action: parts[2], name: nil)
          end
        end
        routes.empty? ? nil : routes
      end

      def parse_routes_file
        routes_file = File.join(@rails_root, 'config', 'routes.rb')
        return nil unless File.exist?(routes_file)

        content = File.read(routes_file)
        routes = extract_routes_from_dsl(content)
        routes.empty? ? nil : routes
      end

      def extract_routes_from_dsl(content)
        routes = []

        content.each_line do |line|
          stripped = line.strip
          next if stripped.start_with?('#') || stripped.empty?

          case stripped
          when /\A(get|post|put|patch|delete)\s+['"]([^'"]+)['"]\s*(?:,\s*to:\s*['"]([^'"]+)['"])?/
            verb = Regexp.last_match(1).upcase
            path = Regexp.last_match(2)
            action = Regexp.last_match(3) || 'unknown'
            routes << Route.new(verb: verb, path: path, controller_action: action, name: nil)
          when /\Aresources?\s+:(\w+)/
            routes.concat(resourceful_routes(Regexp.last_match(1)))
          when /\Aroot\s+['"]([^'"]+)['"]/
            routes << Route.new(verb: 'GET', path: '/', controller_action: Regexp.last_match(1), name: 'root')
          end
        end

        routes
      end

      def resourceful_routes(resource)
        ctrl = resource
        [
          Route.new(verb: 'GET', path: "/#{resource}", controller_action: "#{ctrl}#index", name: nil),
          Route.new(verb: 'GET', path: "/#{resource}/new", controller_action: "#{ctrl}#new", name: nil),
          Route.new(verb: 'POST', path: "/#{resource}", controller_action: "#{ctrl}#create", name: nil),
          Route.new(verb: 'GET', path: "/#{resource}/:id", controller_action: "#{ctrl}#show", name: nil),
          Route.new(verb: 'GET', path: "/#{resource}/:id/edit", controller_action: "#{ctrl}#edit", name: nil),
          Route.new(verb: 'PATCH', path: "/#{resource}/:id", controller_action: "#{ctrl}#update", name: nil),
          Route.new(verb: 'DELETE', path: "/#{resource}/:id", controller_action: "#{ctrl}#destroy", name: nil)
        ]
      end

      def format_route(route)
        { verb: route.verb, path: route.path, action: route.controller_action, name: route.name }.compact
      end

      def route_matches_path?(route, path)
        segment_pattern = Regexp.new(':[^/]+')
        pattern = route.path.gsub(segment_pattern, '[^/]+')
        pattern = pattern.gsub('(.:format)', '(?:\.[^/]+)?')
        Regexp.new("\\A#{pattern}\\z").match?(path)
      rescue RegexpError
        route.path == path
      end

      def error_response(id, code, message)
        { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
      end
    end
  end
end

rails_root = ENV.fetch('RAILS_ROOT', Dir.pwd)
MCPServer::RailsRoutes::Server.new(rails_root).run
