# frozen_string_literal: true

module RubynCode
  module Tasks
    # Directed acyclic graph tracking task dependencies.
    # Backed by a SQLite table for persistence; keeps an in-memory
    # adjacency list for fast traversal.
    class DAG
      # @param db [DB::Connection]
      def initialize(db)
        @db = db
        @forward  = Hash.new { |h, k| h[k] = Set.new } # task_id -> depends_on ids
        @reverse  = Hash.new { |h, k| h[k] = Set.new } # task_id -> dependent ids
        ensure_table
        load_from_db
      end

      # Declares that +task_id+ depends on +depends_on_id+.
      #
      # @param task_id [String]
      # @param depends_on_id [String]
      # @raise [ArgumentError] if this would create a cycle
      # @return [void]
      def add_dependency(task_id, depends_on_id)
        raise ArgumentError, 'A task cannot depend on itself' if task_id == depends_on_id
        raise ArgumentError, 'Cycle detected' if reachable?(depends_on_id, task_id)

        return if @forward[task_id].include?(depends_on_id)

        @db.execute(
          'INSERT OR IGNORE INTO task_dependencies (task_id, depends_on_id) VALUES (?, ?)',
          [task_id, depends_on_id]
        )
        @forward[task_id].add(depends_on_id)
        @reverse[depends_on_id].add(task_id)
      end

      # Removes a dependency edge.
      #
      # @param task_id [String]
      # @param depends_on_id [String]
      # @return [void]
      def remove_dependency(task_id, depends_on_id)
        @db.execute(
          'DELETE FROM task_dependencies WHERE task_id = ? AND depends_on_id = ?',
          [task_id, depends_on_id]
        )
        @forward[task_id].delete(depends_on_id)
        @reverse[depends_on_id].delete(task_id)
      end

      # Returns the IDs of tasks that +task_id+ directly depends on.
      #
      # @param task_id [String]
      # @return [Array<String>]
      def dependencies_for(task_id)
        @forward[task_id].to_a
      end

      # Returns the IDs of tasks that directly depend on +task_id+.
      #
      # @param task_id [String]
      # @return [Array<String>]
      def dependents_of(task_id)
        @reverse[task_id].to_a
      end

      # Returns true if +task_id+ has any incomplete dependency.
      #
      # @param task_id [String]
      # @return [Boolean]
      def blocked?(task_id)
        deps = @forward[task_id]
        return false if deps.empty?

        rows = @db.query(
          "SELECT id FROM tasks WHERE id IN (#{placeholders(deps.size)}) AND status != 'completed'",
          deps.to_a
        ).to_a
        !rows.empty?
      end

      # Called when a task is completed. Removes it as a blocker from
      # every dependent, flipping dependents from 'blocked' to 'pending'
      # when all their deps are met.
      #
      # @param completed_task_id [String]
      # @return [Array<String>] IDs of tasks that were unblocked
      def unblock_cascade(completed_task_id)
        unblocked = []

        dependents_of(completed_task_id).each do |dep_id|
          next if blocked?(dep_id)

          rows = @db.query('SELECT status FROM tasks WHERE id = ?', [dep_id]).to_a
          next if rows.empty?

          current_status = rows.first['status']
          next unless current_status == 'blocked'

          @db.execute(
            "UPDATE tasks SET status = 'pending', updated_at = datetime('now') WHERE id = ?",
            [dep_id]
          )
          unblocked << dep_id
        end

        unblocked
      end

      # Returns all known task IDs in a valid execution order (dependencies first).
      #
      # @return [Array<String>]
      # @raise [RuntimeError] if the graph contains a cycle
      def topological_sort
        all_nodes = collect_all_nodes
        in_degree = compute_in_degrees(all_nodes)

        sorted = kahn_sort(all_nodes, in_degree)
        raise 'Cycle detected in task dependency graph' if sorted.size != all_nodes.size

        sorted
      end

      private

      def collect_all_nodes
        nodes = Set.new
        @forward.each do |task_id, deps|
          nodes.add(task_id)
          deps.each { |dep_id| nodes.add(dep_id) }
        end
        nodes
      end

      def compute_in_degrees(all_nodes)
        in_degree = Hash.new(0)
        all_nodes.each { |n| in_degree[n] = 0 }
        @forward.each { |task_id, deps| in_degree[task_id] += deps.size }
        in_degree
      end

      def kahn_sort(all_nodes, in_degree)
        queue = all_nodes.select { |n| in_degree[n].zero? }
        sorted = []

        until queue.empty?
          node = queue.shift
          sorted << node

          @reverse[node].each do |dependent|
            in_degree[dependent] -= 1
            queue << dependent if in_degree[dependent].zero?
          end
        end

        sorted
      end

      def ensure_table
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS task_dependencies (
            task_id    TEXT NOT NULL,
            depends_on_id TEXT NOT NULL,
            PRIMARY KEY (task_id, depends_on_id),
            FOREIGN KEY (task_id)       REFERENCES tasks(id) ON DELETE CASCADE,
            FOREIGN KEY (depends_on_id) REFERENCES tasks(id) ON DELETE CASCADE
          )
        SQL
      end

      def load_from_db
        rows = @db.query('SELECT task_id, depends_on_id FROM task_dependencies').to_a
        rows.each do |row|
          tid = row['task_id']
          did = row['depends_on_id']
          @forward[tid].add(did)
          @reverse[did].add(tid)
        end
      end

      # Checks if +target+ is reachable from +source+ following forward edges.
      def reachable?(source, target)
        visited = Set.new
        stack = [source]

        until stack.empty?
          node = stack.pop
          next if visited.include?(node)

          return true if node == target

          visited.add(node)
          @forward[node].each { |dep| stack << dep }
        end

        false
      end

      def placeholders(count)
        (['?'] * count).join(', ')
      end
    end
  end
end
