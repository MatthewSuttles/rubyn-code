# frozen_string_literal: true

module RubynCode
  module Autonomous
    # Claims and prepares unclaimed tasks for agent execution.
    # Uses optimistic locking to handle race conditions when multiple
    # agents attempt to claim the same task concurrently.
    module TaskClaimer
      # Finds the first ready (pending, unowned) task, claims it for the
      # given agent, and returns the updated Task. Returns nil if no work
      # is available.
      #
      # @param task_manager [#db, #update_task, #list_tasks] task persistence layer
      # @param agent_name [String] unique identifier of the claiming agent
      # @return [Tasks::Task, nil] the claimed task, or nil if none available
      def self.call(task_manager:, agent_name:)
        db = task_manager.db

        # Atomically claim the first eligible task. The WHERE conditions
        # ensure that only pending tasks with no current owner are touched,
        # avoiding race conditions with other agents.
        db.execute(<<~SQL, [agent_name])
          UPDATE tasks
          SET owner = ?,
              status = 'in_progress',
              updated_at = datetime('now')
          WHERE id = (
            SELECT id FROM tasks
            WHERE status = 'pending'
              AND (owner IS NULL OR owner = '')
            ORDER BY priority DESC, created_at ASC
            LIMIT 1
          )
          AND status = 'pending'
          AND (owner IS NULL OR owner = '')
        SQL

        # Fetch the task we just claimed. Using owner + status filters
        # ensures we only retrieve a task that *this* agent successfully
        # claimed (another agent cannot have flipped it in between).
        rows = db.query(<<~SQL, [agent_name]).to_a
          SELECT id, session_id, title, description, status,
                 priority, owner, result, metadata, created_at, updated_at
          FROM tasks
          WHERE owner = ?
            AND status = 'in_progress'
          ORDER BY updated_at DESC
          LIMIT 1
        SQL

        return nil if rows.empty?

        row = rows.first
        build_task(row)
      rescue StandardError => e
        # If anything goes wrong (e.g. task was already claimed between
        # our SELECT and UPDATE, or a constraint violation) we treat it
        # as "no work available" rather than crashing the daemon.
        RubynCode.logger.warn("TaskClaimer: failed to claim task: #{e.message}") if RubynCode.respond_to?(:logger)
        nil
      end

      class << self
        private

        # @param row [Hash] a database row hash
        # @return [Tasks::Task]
        def build_task(row)
          metadata = parse_json(row["metadata"])

          Tasks::Task.new(
            id: row["id"],
            session_id: row["session_id"],
            title: row["title"],
            description: row["description"],
            status: row["status"],
            priority: row["priority"].to_i,
            owner: row["owner"],
            result: row["result"],
            metadata: metadata,
            created_at: row["created_at"],
            updated_at: row["updated_at"]
          )
        end

        # @param raw [String, Hash, nil]
        # @return [Hash]
        def parse_json(raw)
          case raw
          when Hash then raw
          when String then JSON.parse(raw, symbolize_names: true)
          else {}
          end
        rescue JSON::ParserError
          {}
        end
      end
    end
  end
end
