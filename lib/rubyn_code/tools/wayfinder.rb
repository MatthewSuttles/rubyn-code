# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    # Gives agents a purpose-built control surface for Harness Wayfinder maps.
    # The desktop host observes these audited calls and owns every mutation.
    class Wayfinder < Base
      TOOL_NAME = 'wayfinder'
      DESCRIPTION = 'Read and update Rubyn Harness Wayfinder maps. Use this to shape a map, add dependency nodes, record settled decisions, or retire obsolete nodes when RUBYN_HARNESS_CONTROL_FILE is present.'
      PARAMETERS = {
        action: { type: :string, required: true,
                  description: 'list_maps, get_map, create_map, import_map, update_map, create_node, resolve_node, or retire_node' },
        map_id: { type: :string, required: false, description: 'Numeric Wayfinder map ID or exact map title' },
        node_id: { type: :string, required: false, description: 'Numeric Wayfinder node ID' },
        title: { type: :string, required: false, description: 'Map or node title' },
        idea: { type: :string, required: false, description: 'Loose idea behind a newly imported map' },
        destination: { type: :string, required: false, description: 'Observable destination for the map' },
        notes: { type: :string, required: false, description: 'Standing map instructions and boundaries' },
        code_task_status: { type: :string, required: false,
                            description: 'Harness workflow column key chosen by the human for materialized code tasks' },
        node_type: { type: :string, required: false,
                     description: 'grill, research, prototype, code, or user_action' },
        question: { type: :string, required: false, description: 'Decision or uncertainty this node settles' },
        description: { type: :string, required: false, description: 'Context the node needs' },
        outcome: { type: :string, required: false, description: 'Observable evidence that completes the node' },
        resolution: { type: :string, required: false, description: 'Approved answer or evidence for the node' },
        model_role: { type: :string, required: false, description: 'Sol or Terra' },
        effort: { type: :string, required: false, description: 'low, medium, or high' },
        blocked_by: { type: :array, required: false,
                      description: 'Earlier node IDs or exact titles this node depends on' }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def execute(action:, map_id: nil, node_id: nil, title: nil, idea: nil, destination: nil, notes: nil,
                  code_task_status: nil,
                  node_type: nil, question: nil, description: nil, outcome: nil, resolution: nil,
                  model_role: nil, effort: nil, blocked_by: [])
        maps = snapshot.fetch('wayfinder', [])
        case action.to_s
        when 'list_maps'
          return 'There are no Wayfinder maps in this project.' if maps.empty?

          maps.map { |entry| "[#{entry.dig('map', 'status')}] map ##{entry.dig('map', 'id')} #{entry.dig('map', 'title')}" }.join("\n")
        when 'get_map'
          map = maps.find { |entry| entry.dig('map', 'id').to_s == map_id.to_s }
          map ? JSON.pretty_generate(map) : "No Wayfinder map found with ID #{map_id}."
        when 'create_map'
          "Requested new Wayfinder map: #{title || idea}. Add nodes using that exact title as map_id."
        when 'import_map'
          "Requested imported Wayfinder map: #{title || idea}. The blank bootstrap node will be removed; add imported nodes using that exact title as map_id."
        when 'update_map'
          "Requested update to Wayfinder map #{map_id}."
        when 'create_node'
          "Requested #{node_type || 'grill'} node on Wayfinder map #{map_id}: #{title}."
        when 'resolve_node'
          "Requested resolution of Wayfinder node #{node_id}."
        when 'retire_node'
          "Requested retirement of Wayfinder node #{node_id}."
        else
          raise Error, 'wayfinder action must be list_maps, get_map, create_map, import_map, update_map, create_node, resolve_node, or retire_node'
        end
      end

      def self.summarize(_output, args)
        action = args['action'] || args[:action]
        subject = args['title'] || args[:title] || args['node_id'] || args[:node_id] || args['map_id'] || args[:map_id]
        "Wayfinder #{action.to_s.tr('_', ' ')}#{subject ? ": #{subject}" : ''}"
      end

      private

      def snapshot
        path = ENV.fetch('RUBYN_HARNESS_CONTROL_FILE', '')
        raise Error, 'Rubyn Harness control plane is not connected' if path.empty? || !File.file?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise Error, "Rubyn Harness control snapshot is invalid: #{e.message}"
      end
    end

    Registry.register(Wayfinder)
  end
end
