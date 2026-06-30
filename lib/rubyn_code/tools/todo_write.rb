# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    # Update the in-turn task checklist. The model uses this to keep the user
    # informed of progress while it works. The store is shared between the
    # Agent::Loop (which exposes it for the renderer) and this tool.
    class TodoWrite < Base
      TOOL_NAME = 'TodoWrite'
      DESCRIPTION = 'Update the in-turn task checklist. ' \
                    'Use this to keep the user informed of what you plan to do, ' \
                    'what you are currently working on, and what you have finished.'
      PARAMETERS = {
        todos: { type: :array, required: true,
                 description: 'The full set of tasks currently on the checklist. ' \
                              'Replace the existing list with this. Each task is ' \
                              '{ "content": "...", "status": "pending|in_progress|completed", ' \
                              '"active_form": "..." }.' }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      VALID_STATUS = %w[pending in_progress completed].freeze

      def initialize(project_root:, store: nil)
        super(project_root: project_root)
        @store = store
      end

      def execute(todos:)
        items = Array(todos)
        validated = []

        items.each_with_index do |item, i|
          return "TodoWrite: item #{i} is not a hash — got #{item.class}" unless item.is_a?(Hash)

          content = item[:content] || item['content']
          status  = (item[:status] || item['status']).to_s
          active_form = item[:active_form] || item['active_form']

          return "TodoWrite: item #{i} missing 'content'" if content.to_s.empty?
          unless VALID_STATUS.include?(status)
            return "TodoWrite: item #{i} status must be one of #{VALID_STATUS.join('/')} (got #{status.inspect})"
          end

          validated << {
            'content' => content.to_s,
            'status' => status,
            'active_form' => active_form.to_s.empty? ? content.to_s : active_form.to_s
          }
        end

        @store&.replace(validated)
        format(validated)
      end

      def self.summarize(_output, _args)
        count = Array(_args[:todos] || _args['todos']).size
        if count.zero?
          'cleared checklist'
        else
          "checklist: #{count} item#{'s' unless count == 1}"
        end
      end

      private

      def format(items)
        return 'Checklist cleared.' if items.empty?

        items.map do |item|
          mark =
            case item['status']
            when 'completed' then '[x]'
            when 'in_progress' then '[~]'
            else '[ ]'
            end
          "#{mark} #{item['content']}"
        end.join("\n")
      end
    end

    Registry.register(TodoWrite)
  end
end
