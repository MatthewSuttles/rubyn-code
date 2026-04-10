# frozen_string_literal: true

module RubynCode
  module Autonomous
    # Claims and prepares unclaimed tasks for agent execution.
    # Uses optimistic locking to handle race conditions when multiple
    # agents attempt to claim the same task concurrently.
    module TaskClaimer
      MAX_RETRIES = 3

      # Finds the first ready (pending, unowned) task that hasn't exceeded
      # max retries, claims it for the given agent, and returns the updated
      # Task. Returns nil if no work is available.
      #
      # @param task_manager [#db, #update_task, #list_tasks] task persistence layer
      # @param agent_name [String] unique identifier of the claiming agent
      # @param max_retries [Integer] maximum retry count before skipping a task
      # @return [Tasks::Task, nil] the claimed task, or nil if none available
      def self.call(task_manager:, agent_name:, max_retries: MAX_RETRIES)
        db = task_manager.db
        claim_next_pending_task(db, agent_name, max_retries)
        fetch_claimed_task(db, agent_name)
      rescue StandardError => e
        RubynCode.logger.warn("TaskClaimer: failed to claim task: #{e.message}") if RubynCode.respond_to?(:logger)
        nil
      end

      class << self
        private

        def claim_next_pending_task(db, agent_name, max_retries)
          db.execute(<<~SQL, [agent_name, max_retries])
            UPDATE tasks
            SET owner = ?,
                status = 'in_progress',
                updated_at = datetime('now')
            WHERE id = (
              SELECT t.id FROM tasks t
              WHERE t.status = 'pending'
                AND (t.owner IS NULL OR t.owner = '')
                AND COALESCE(
                  json_extract(t.metadata, '$.retry_count'), 0
                ) < ?
              ORDER BY t.priority DESC, t.created_at ASC
              LIMIT 1
            )
            AND status = 'pending'
            AND (owner IS NULL OR owner = '')
          SQL
        end

        def fetch_claimed_task(db, agent_name)
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

          build_task(rows.first)
        end

        # @param row [Hash] a database row hash
        # @return [Tasks::Task]
        def build_task(row)
          metadata = parse_json(row['metadata'])

          Tasks::Task.new(
            id: row['id'],
            session_id: row['session_id'],
            title: row['title'],
            description: row['description'],
            status: row['status'],
            priority: row['priority'].to_i,
            owner: row['owner'],
            result: row['result'],
            metadata: metadata,
            created_at: row['created_at'],
            updated_at: row['updated_at']
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
