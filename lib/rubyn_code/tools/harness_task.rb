# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    # Operates on the shared Rubyn Harness board. The desktop host observes
    # these audited tool calls and applies them to its durable project store.
    class HarnessTask < Base
      TOOL_NAME = 'harness_task'
      DESCRIPTION = 'Read or manage Rubyn Harness tasks, todos, and Wayfinder maps. ' \
                    'Use this for app-native planning and board changes when RUBYN_HARNESS_CONTROL_FILE is present.'
      PARAMETERS = {
        kind: { type: :string, required: true, description: 'task, todo, or wayfinder' },
        action: { type: :string, required: true,
                  description: 'Task/todo: list, get, create, update, complete. Wayfinder: list, get, update_map, create_node, resolve_node, retire_node.' },
        task_id: { type: :string, required: false, description: 'Numeric task, todo, or Wayfinder node ID' },
        map_id: { type: :string, required: false, description: 'Numeric Wayfinder map ID' },
        title: { type: :string, required: false, description: 'Title for a task, todo, map, or node' },
        description: { type: :string, required: false, description: 'Task detail or Wayfinder node information' },
        question: { type: :string, required: false, description: 'Decision or investigation the Wayfinder node resolves' },
        outcome: { type: :string, required: false, description: 'Observable evidence required for completion' },
        destination: { type: :string, required: false, description: 'Observable destination for a Wayfinder map' },
        notes: { type: :string, required: false, description: 'Standing instructions for a Wayfinder map' },
        resolution: { type: :string, required: false, description: 'Approved resolution for a Wayfinder node' },
        node_type: { type: :string, required: false,
                     description: 'grill, research, prototype, code, or user_action. Unblocked code nodes become Tasks after map activation.' },
        model_role: { type: :string, required: false, description: 'Sol or Terra' },
        effort: { type: :string, required: false, description: 'low, medium, or high' },
        status: { type: :string, required: false,
                  description: 'pending, in_progress, review, blocked, or completed' },
        blocked_by: { type: :array, required: false, description: 'Numeric task or Wayfinder node dependency IDs' }
      }.freeze
      # The Harness host performs and audits the mutation; Rubyn itself only
      # reads the host-owned snapshot, so this must not enter the file-edit gate.
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def execute(kind:, action:, task_id: nil, map_id: nil, title: nil, description: nil,
                  question: nil, outcome: nil, destination: nil, notes: nil, resolution: nil,
                  node_type: nil, model_role: nil, effort: nil, status: nil, blocked_by: [])
        data = snapshot
        return execute_wayfinder(data, action, task_id: task_id, map_id: map_id, title: title,
                                               node_type: node_type) if kind.to_s == 'wayfinder'

        collection = kind.to_s == 'todo' ? data.fetch('todos', []) : data.fetch('tasks', [])
        case action.to_s
        when 'list'
          format_items(collection)
        when 'get'
          item = collection.find { |candidate| candidate['id'].to_s == task_id.to_s }
          item ? JSON.pretty_generate(item) : "No #{kind} found with ID #{task_id}."
        when 'create'
          "Requested shared #{kind}: #{title}. Rubyn Harness will add it to the board."
        when 'update'
          "Requested update to shared #{kind} #{task_id}#{status ? " → #{status}" : ''}."
        when 'complete'
          "Requested completion of shared #{kind} #{task_id}."
        else
          raise Error, 'task/todo action must be list, get, create, update, or complete'
        end
      end

      def self.summarize(_output, args)
        "Harness #{args['kind'] || args[:kind]} #{args['action'] || args[:action]}"
      end

      private

      def execute_wayfinder(data, action, task_id:, map_id:, title:, node_type:)
        maps = data.fetch('wayfinder', [])
        case action.to_s
        when 'list'
          maps.map { |entry| "[#{entry.dig('map', 'status')}] map ##{entry.dig('map', 'id')} #{entry.dig('map', 'title')}" }.join("\n")
        when 'get'
          map = maps.find { |entry| entry.dig('map', 'id').to_s == map_id.to_s }
          map ? JSON.pretty_generate(map) : "No Wayfinder map found with ID #{map_id}."
        when 'update_map'
          "Requested update to Wayfinder map #{map_id}."
        when 'create_node'
          "Requested #{node_type || 'grill'} node on Wayfinder map #{map_id}: #{title}."
        when 'resolve_node'
          "Requested resolution of Wayfinder node #{task_id}."
        when 'retire_node'
          "Requested retirement of Wayfinder node #{task_id}."
        else
          raise Error, 'wayfinder action must be list, get, update_map, create_node, resolve_node, or retire_node'
        end
      end

      def snapshot
        path = ENV.fetch('RUBYN_HARNESS_CONTROL_FILE', '')
        raise Error, 'Rubyn Harness control plane is not connected' if path.empty? || !File.file?(path)

        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise Error, "Rubyn Harness control snapshot is invalid: #{e.message}"
      end

      def format_items(items)
        return 'The shared Harness board is empty.' if items.empty?

        items.map do |item|
          dependencies = Array(item['dependsOn']).map { |id| "##{id}" }.join(', ')
          line = "[#{item['status']}] ##{item['id']} #{item['title']}"
          dependencies.empty? ? line : "#{line} (blocked by #{dependencies})"
        end.join("\n")
      end
    end

    Registry.register(HarnessTask)
  end
end
