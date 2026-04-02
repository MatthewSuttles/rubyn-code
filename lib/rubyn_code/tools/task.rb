# frozen_string_literal: true

require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class Task < Base
      TOOL_NAME = "task"
      DESCRIPTION = "Manage tasks: create, update, complete, list, or get tasks for tracking work items and dependencies."
      PARAMETERS = {
        action: {
          type: :string, required: true,
          description: "Action to perform: create, update, complete, list, get"
        },
        title: {
          type: :string, required: false,
          description: "Task title (required for create)"
        },
        description: {
          type: :string, required: false,
          description: "Task description"
        },
        task_id: {
          type: :string, required: false,
          description: "Task ID (required for update, complete, get)"
        },
        status: {
          type: :string, required: false,
          description: "Filter by status (for list) or set status (for update)"
        },
        session_id: {
          type: :string, required: false,
          description: "Session ID for scoping tasks"
        },
        priority: {
          type: :integer, required: false,
          description: "Task priority (higher = more important)"
        },
        blocked_by: {
          type: :array, required: false,
          description: "Array of task IDs this task depends on (for create)"
        },
        result: {
          type: :string, required: false,
          description: "Result text (for complete)"
        },
        owner: {
          type: :string, required: false,
          description: "Owner identifier (for update)"
        }
      }.freeze
      RISK_LEVEL = :write
      REQUIRES_CONFIRMATION = false

      def execute(action:, **params)
        manager = Tasks::Manager.new(DB::Connection.instance)

        case action
        when "create"  then execute_create(manager, **params)
        when "update"  then execute_update(manager, **params)
        when "complete" then execute_complete(manager, **params)
        when "list"    then execute_list(manager, **params)
        when "get"     then execute_get(manager, **params)
        else
          raise Error, "Unknown task action: #{action}. Valid actions: create, update, complete, list, get"
        end
      end

      private

      def execute_create(manager, title: nil, description: nil, session_id: nil, blocked_by: [], priority: 0, **)
        raise Error, "title is required for create" if title.nil? || title.empty?

        task = manager.create(
          title: title,
          description: description,
          session_id: session_id,
          blocked_by: Array(blocked_by),
          priority: priority.to_i
        )

        format_task(task, prefix: "Created task")
      end

      def execute_update(manager, task_id: nil, **params)
        raise Error, "task_id is required for update" if task_id.nil? || task_id.empty?

        attrs = params.slice(:status, :priority, :owner, :result, :description, :title, :metadata)
        attrs[:priority] = attrs[:priority].to_i if attrs.key?(:priority)

        task = manager.update(task_id, **attrs)
        raise Error, "Task not found: #{task_id}" if task.nil?

        format_task(task, prefix: "Updated task")
      end

      def execute_complete(manager, task_id: nil, result: nil, **)
        raise Error, "task_id is required for complete" if task_id.nil? || task_id.empty?

        task = manager.complete(task_id, result: result)
        raise Error, "Task not found: #{task_id}" if task.nil?

        format_task(task, prefix: "Completed task")
      end

      def execute_list(manager, status: nil, session_id: nil, **)
        tasks = manager.list(status: status, session_id: session_id)

        return "No tasks found." if tasks.empty?

        lines = tasks.map { |t| format_task_line(t) }
        "Found #{tasks.size} task(s):\n\n#{lines.join("\n")}"
      end

      def execute_get(manager, task_id: nil, **)
        raise Error, "task_id is required for get" if task_id.nil? || task_id.empty?

        task = manager.get(task_id)
        raise Error, "Task not found: #{task_id}" if task.nil?

        format_task(task)
      end

      def format_task(task, prefix: nil)
        header = prefix ? "#{prefix}: #{task.title}" : task.title
        parts = [
          header,
          "  ID:       #{task.id}",
          "  Status:   #{task.status}",
          "  Priority: #{task.priority}"
        ]
        parts << "  Owner:    #{task.owner}" if task.owner
        parts << "  Result:   #{task.result}" if task.result
        parts << "  Session:  #{task.session_id}" if task.session_id
        parts << "  Description: #{task.description}" if task.description
        parts.join("\n")
      end

      def format_task_line(task)
        owner_part = task.owner ? " (#{task.owner})" : ""
        "[#{task.status}] #{task.title} (#{task.id[0, 8]}...)#{owner_part} priority=#{task.priority}"
      end
    end

    Registry.register(Task)
  end
end
