# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative 'teammate'

module RubynCode
  module Teams
    # CRUD manager for teammates backed by SQLite.
    #
    # Provides lifecycle management for agent teammates: spawning,
    # listing, status updates, removal, and parent-child discovery.
    class Manager
      # @param db [DB::Connection] the database connection
      # @param mailbox [Mailbox] the team mailbox for inter-agent messaging
      def initialize(db, mailbox:)
        @db = db
        @mailbox = mailbox
        ensure_table!
      end

      # Creates a new teammate record.
      #
      # @param name [String] unique teammate name
      # @param role [String] the teammate's role description
      # @param persona [String, nil] optional persona prompt
      # @param model [String, nil] optional LLM model override
      # @param parent_agent_id [String, nil] ID of the parent agent that spawned this teammate
      # @return [Teammate] the newly created teammate
      # @raise [Error] if a teammate with the given name already exists
      def spawn(name:, role:, persona: nil, model: nil, parent_agent_id: nil)
        existing = get(name)
        raise Error, "Teammate '#{name}' already exists" if existing

        id = SecureRandom.uuid
        now = Time.now.utc.iso8601
        metadata_json = JSON.generate({})

        @db.execute(
          <<~SQL,
            INSERT INTO teammates (id, name, role, persona, model, status, parent_agent_id, metadata, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [id, name, role, persona, model, 'idle', parent_agent_id, metadata_json, now]
        )

        Teammate.new(
          id: id,
          name: name,
          role: role,
          persona: persona,
          model: model,
          status: 'idle',
          parent_agent_id: parent_agent_id,
          metadata: {},
          created_at: now
        )
      end

      # Returns all teammates.
      #
      # @return [Array<Teammate>]
      def list
        rows = @db.query('SELECT * FROM teammates ORDER BY created_at ASC').to_a
        rows.map { |row| row_to_teammate(row) }
      end

      # Finds a teammate by name.
      #
      # @param name [String]
      # @return [Teammate, nil]
      def get(name)
        rows = @db.query('SELECT * FROM teammates WHERE name = ? LIMIT 1', [name]).to_a
        return nil if rows.empty?

        row_to_teammate(rows.first)
      end

      # Finds a teammate by ID.
      #
      # @param id [String]
      # @return [Teammate, nil]
      def find_by_id(id)
        rows = @db.query('SELECT * FROM teammates WHERE id = ? LIMIT 1', [id]).to_a
        return nil if rows.empty?

        row_to_teammate(rows.first)
      end

      # Returns all direct children of the given parent agent.
      #
      # @param parent_id [String] the parent agent's ID
      # @return [Array<Teammate>]
      def children_of(parent_id)
        rows = @db.query(
          'SELECT * FROM teammates WHERE parent_agent_id = ? ORDER BY created_at ASC',
          [parent_id]
        ).to_a
        rows.map { |row| row_to_teammate(row) }
      end

      # Returns all root agents (those with no parent).
      #
      # @return [Array<Teammate>]
      def roots
        rows = @db.query(
          'SELECT * FROM teammates WHERE parent_agent_id IS NULL ORDER BY created_at ASC'
        ).to_a
        rows.map { |row| row_to_teammate(row) }
      end

      # Builds a full agent tree from a root agent ID.
      # Returns a nested hash: { agent: Teammate, children: [{ agent:, children: }, ...] }
      #
      # @param root_id [String] the root agent's ID
      # @return [Hash, nil] nested tree structure or nil if root not found
      def agent_tree(root_id)
        root = find_by_id(root_id)
        return nil unless root

        build_tree_node(root)
      end

      # Updates a teammate's status.
      #
      # @param name [String]
      # @param status [String] one of "idle", "active", "offline"
      # @return [void]
      # @raise [ArgumentError] if the status is invalid
      # @raise [Error] if the teammate is not found
      def update_status(name, status)
        unless VALID_STATUSES.include?(status)
          raise ArgumentError, "Invalid status '#{status}'. Must be one of: #{VALID_STATUSES.join(', ')}"
        end

        teammate = get(name)
        raise Error, "Teammate '#{name}' not found" unless teammate

        @db.execute(
          'UPDATE teammates SET status = ? WHERE name = ?',
          [status, name]
        )
      end

      # Removes a teammate by name.
      #
      # @param name [String]
      # @return [void]
      # @raise [Error] if the teammate is not found
      def remove(name)
        teammate = get(name)
        raise Error, "Teammate '#{name}' not found" unless teammate

        @db.execute('DELETE FROM teammates WHERE name = ?', [name])
      end

      # Returns all teammates with status "active".
      #
      # @return [Array<Teammate>]
      def active_teammates
        rows = @db.query(
          'SELECT * FROM teammates WHERE status = ? ORDER BY created_at ASC',
          ['active']
        ).to_a
        rows.map { |row| row_to_teammate(row) }
      end

      private

      # Recursively builds a tree node for an agent and its children.
      #
      # @param agent [Teammate]
      # @return [Hash]
      def build_tree_node(agent)
        kids = children_of(agent.id)
        {
          agent: agent,
          children: kids.map { |child| build_tree_node(child) }
        }
      end

      # Converts a database row hash to a Teammate value object.
      #
      # @param row [Hash]
      # @return [Teammate]
      def row_to_teammate(row)
        metadata = parse_metadata(row['metadata'])

        Teammate.new(
          id: row['id'],
          name: row['name'],
          role: row['role'],
          persona: row['persona'],
          model: row['model'],
          status: row['status'],
          parent_agent_id: row['parent_agent_id'],
          metadata: metadata,
          created_at: row['created_at']
        )
      end

      # Safely parses JSON metadata, returning an empty hash on failure.
      #
      # @param raw [String, nil]
      # @return [Hash]
      def parse_metadata(raw)
        return {} if raw.nil? || raw.empty?

        JSON.parse(raw, symbolize_names: true)
      rescue JSON::ParserError
        {}
      end

      # Creates the teammates table if it does not already exist.
      def ensure_table!
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS teammates (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            role TEXT NOT NULL,
            persona TEXT,
            model TEXT,
            status TEXT NOT NULL DEFAULT 'idle',
            parent_agent_id TEXT,
            metadata TEXT NOT NULL DEFAULT '{}',
            created_at TEXT NOT NULL
          )
        SQL

        # Self-heal: add columns that later migrations added to legacy
        # tables.  Same pattern as Mailbox#ensure_table!.
        add_teammate_column_if_missing('parent_agent_id')
        add_teammate_column_if_missing('metadata')

        @db.execute(<<~SQL)
          CREATE UNIQUE INDEX IF NOT EXISTS idx_teammates_name ON teammates (name)
        SQL

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_teammates_parent ON teammates (parent_agent_id)
        SQL
      end

      # @return [Boolean] true if the column was added
      def add_teammate_column_if_missing(column)
        @db.execute("ALTER TABLE teammates ADD COLUMN #{column} TEXT")
        true
      rescue SQLite3::SQLException
        false
      end
    end
  end
end
