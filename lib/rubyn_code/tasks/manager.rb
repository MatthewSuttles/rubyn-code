# frozen_string_literal: true

require "securerandom"
require_relative "models"
require_relative "dag"

module RubynCode
  module Tasks
    # CRUD manager for tasks backed by SQLite.
    class Manager
      attr_reader :db

      # @param db [DB::Connection]
      def initialize(db)
        @db = db
        ensure_table
        @dag = DAG.new(db)
      end

      # Creates a new task and persists it.
      #
      # @param title [String]
      # @param description [String, nil]
      # @param session_id [String, nil]
      # @param blocked_by [Array<String>] IDs of tasks this one depends on
      # @param priority [Integer]
      # @return [Task]
      def create(title:, description: nil, session_id: nil, blocked_by: [], priority: 0)
        id = SecureRandom.uuid
        now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
        status = blocked_by.empty? ? "pending" : "blocked"

        @db.transaction do
          @db.execute(<<~SQL, [id, session_id, title, description, status, priority, now, now])
            INSERT INTO tasks (id, session_id, title, description, status, priority, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          SQL

          blocked_by.each do |dep_id|
            @dag.add_dependency(id, dep_id)
          end
        end

        get(id)
      end

      # Updates arbitrary attributes on a task.
      #
      # @param id [String]
      # @param attrs [Hash] supported keys: status, priority, owner, result, description, title, metadata
      # @return [Task]
      def update(id, **attrs)
        allowed = %i[status priority owner result description title metadata]
        filtered = attrs.select { |k, _| allowed.include?(k) }
        return get(id) if filtered.empty?

        sets = filtered.map { |k, _| "#{k} = ?" }
        sets << "updated_at = datetime('now')"
        values = filtered.values
        values << id

        @db.execute(
          "UPDATE tasks SET #{sets.join(', ')} WHERE id = ?",
          values
        )

        get(id)
      end

      # Marks a task as completed and cascades unblocking via the DAG.
      #
      # @param id [String]
      # @param result [String, nil]
      # @return [Task]
      def complete(id, result: nil)
        sets = ["status = 'completed'", "updated_at = datetime('now')"]
        values = []

        if result
          sets << "result = ?"
          values << result
        end

        values << id

        @db.execute(
          "UPDATE tasks SET #{sets.join(', ')} WHERE id = ?",
          values
        )

        @dag.unblock_cascade(id)

        get(id)
      end

      # Claims a task by setting the owner and moving it to in_progress.
      #
      # @param id [String]
      # @param owner [String]
      # @return [Task]
      def claim(id, owner:)
        @db.execute(
          "UPDATE tasks SET owner = ?, status = 'in_progress', updated_at = datetime('now') WHERE id = ?",
          [owner, id]
        )

        get(id)
      end

      # Fetches a single task by ID.
      #
      # @param id [String]
      # @return [Task, nil]
      def get(id)
        rows = @db.query("SELECT * FROM tasks WHERE id = ?", [id]).to_a
        row_to_task(rows.first)
      end

      # Lists tasks with optional filters.
      #
      # @param status [String, nil]
      # @param session_id [String, nil]
      # @return [Array<Task>]
      def list(status: nil, session_id: nil)
        conditions = []
        params = []

        if status
          conditions << "status = ?"
          params << status
        end

        if session_id
          conditions << "session_id = ?"
          params << session_id
        end

        sql = "SELECT * FROM tasks"
        sql += " WHERE #{conditions.join(' AND ')}" unless conditions.empty?
        sql += " ORDER BY priority DESC, created_at ASC"

        @db.query(sql, params).to_a.filter_map { |row| row_to_task(row) }
      end

      # Returns tasks that are pending, unowned, and have no unmet dependencies.
      #
      # @return [Array<Task>]
      def ready_tasks
        rows = @db.query(
          "SELECT * FROM tasks WHERE status = 'pending' AND owner IS NULL ORDER BY priority DESC, created_at ASC"
        ).to_a

        rows.filter_map { |row| row_to_task(row) }
            .reject { |task| @dag.blocked?(task.id) }
      end

      # Deletes a task and its dependency edges (via CASCADE).
      #
      # @param id [String]
      # @return [void]
      def delete(id)
        @db.execute("DELETE FROM tasks WHERE id = ?", [id])
      end

      private

      def ensure_table
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS tasks (
            id          TEXT PRIMARY KEY,
            session_id  TEXT,
            title       TEXT NOT NULL,
            description TEXT,
            status      TEXT NOT NULL DEFAULT 'pending',
            priority    INTEGER NOT NULL DEFAULT 0,
            owner       TEXT,
            result      TEXT,
            metadata    TEXT,
            created_at  TEXT NOT NULL,
            updated_at  TEXT NOT NULL
          )
        SQL

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status)
        SQL

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_tasks_session ON tasks(session_id)
        SQL
      end

      def row_to_task(row)
        return nil if row.nil?

        Task.new(
          id:          row["id"],
          session_id:  row["session_id"],
          title:       row["title"],
          description: row["description"],
          status:      row["status"],
          priority:    row["priority"],
          owner:       row["owner"],
          result:      row["result"],
          metadata:    row["metadata"],
          created_at:  row["created_at"],
          updated_at:  row["updated_at"]
        )
      end
    end
  end
end
