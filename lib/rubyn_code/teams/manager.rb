# frozen_string_literal: true

require 'json'
require 'securerandom'
require_relative 'teammate'

module RubynCode
  module Teams
    # CRUD manager for teammates backed by SQLite.
    #
    # Provides lifecycle management for agent teammates: spawning,
    # listing, status updates, and removal.
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
      # @return [Teammate] the newly created teammate
      # @raise [Error] if a teammate with the given name already exists
      def spawn(name:, role:, persona: nil, model: nil)
        existing = get(name)
        raise Error, "Teammate '#{name}' already exists" if existing

        id = SecureRandom.uuid
        now = Time.now.utc.iso8601
        metadata_json = JSON.generate({})

        @db.execute(
          <<~SQL,
            INSERT INTO teammates (id, name, role, persona, model, status, metadata, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [id, name, role, persona, model, 'idle', metadata_json, now]
        )

        Teammate.new(
          id: id,
          name: name,
          role: role,
          persona: persona,
          model: model,
          status: 'idle',
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
            metadata TEXT NOT NULL DEFAULT '{}',
            created_at TEXT NOT NULL
          )
        SQL

        @db.execute(<<~SQL)
          CREATE UNIQUE INDEX IF NOT EXISTS idx_teammates_name ON teammates (name)
        SQL
      end
    end
  end
end
