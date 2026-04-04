# frozen_string_literal: true

require 'securerandom'
require 'json'

module RubynCode
  module Memory
    # Saves and restores full conversation sessions to SQLite, enabling
    # session continuity across process restarts and session browsing.
    class SessionPersistence
      # @param db [DB::Connection] database connection
      def initialize(db)
        @db = db
        ensure_table
      end

      # Persists a complete session snapshot.
      #
      # @param session_id [String] unique session identifier
      # @param project_path [String] project this session belongs to
      # @param messages [Array<Hash>] the conversation messages
      # @param title [String, nil] human-readable session title
      # @param model [String, nil] LLM model used
      # @param metadata [Hash] arbitrary metadata
      # @return [void]
      def save_session(session_id:, project_path:, messages:, title: nil, model: nil, metadata: {})
        now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
        messages_json = JSON.generate(messages)
        meta_json = JSON.generate(metadata)

        @db.execute(<<~SQL, [session_id, project_path, title, model, messages_json, 'active', meta_json, now, now, messages_json, title, model, meta_json, now])
          INSERT INTO sessions (id, project_path, title, model, messages, status, metadata, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            messages = ?,
            title = COALESCE(?, title),
            model = COALESCE(?, model),
            metadata = ?,
            updated_at = ?
        SQL
      end

      # Loads a session by ID.
      #
      # @param session_id [String]
      # @return [Hash, nil] { messages:, metadata:, title:, model:, status:, project_path: } or nil
      def load_session(session_id)
        rows = @db.query(
          'SELECT * FROM sessions WHERE id = ?',
          [session_id]
        ).to_a
        return nil if rows.empty?

        row = rows.first
        {
          messages: parse_json_array(row['messages']),
          metadata: parse_json_hash(row['metadata']),
          title: row['title'],
          model: row['model'],
          status: row['status'],
          project_path: row['project_path'],
          created_at: row['created_at'],
          updated_at: row['updated_at']
        }
      end

      # Lists sessions, optionally filtered by project and/or status.
      #
      # @param project_path [String, nil] filter by project
      # @param status [String, nil] filter by status ("active", "archived", "deleted")
      # @param limit [Integer] maximum results (default 20)
      # @return [Array<Hash>] session summaries (without full messages)
      def list_sessions(project_path: nil, status: nil, limit: 20)
        conditions = []
        params = []

        if project_path
          conditions << 'project_path = ?'
          params << project_path
        end

        if status
          conditions << 'status = ?'
          params << status
        end

        where_clause = conditions.empty? ? '' : "WHERE #{conditions.join(' AND ')}"
        params << limit

        rows = @db.query(<<~SQL, params).to_a
          SELECT id, project_path, title, model, status, metadata, created_at, updated_at
          FROM sessions
          #{where_clause}
          ORDER BY updated_at DESC
          LIMIT ?
        SQL

        rows.map do |row|
          {
            id: row['id'],
            project_path: row['project_path'],
            title: row['title'],
            model: row['model'],
            status: row['status'],
            metadata: parse_json_hash(row['metadata']),
            created_at: row['created_at'],
            updated_at: row['updated_at']
          }
        end
      end

      # Updates session attributes.
      #
      # @param session_id [String]
      # @param attrs [Hash] attributes to update (:title, :status, :model, :metadata, :messages)
      # @return [void]
      def update_session(session_id, **attrs)
        return if attrs.empty?

        sets = []
        params = []

        attrs.each do |key, value|
          case key
          when :title
            sets << 'title = ?'
            params << value
          when :status
            sets << 'status = ?'
            params << value
          when :model
            sets << 'model = ?'
            params << value
          when :metadata
            sets << 'metadata = ?'
            params << JSON.generate(value)
          when :messages
            sets << 'messages = ?'
            params << JSON.generate(value)
          end
        end

        return if sets.empty?

        sets << 'updated_at = ?'
        params << Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
        params << session_id

        @db.execute("UPDATE sessions SET #{sets.join(', ')} WHERE id = ?", params)
      end

      # Deletes a session permanently.
      #
      # @param session_id [String]
      # @return [void]
      def delete_session(session_id)
        @db.execute('DELETE FROM sessions WHERE id = ?', [session_id])
      end

      private

      def ensure_table
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS sessions (
            id TEXT PRIMARY KEY,
            project_path TEXT NOT NULL,
            title TEXT,
            model TEXT,
            messages TEXT NOT NULL DEFAULT '[]',
            status TEXT NOT NULL DEFAULT 'active',
            metadata TEXT DEFAULT '{}',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        SQL

        # Add messages column for databases created by the original migration
        # (001_create_sessions.sql) which omitted it
        @db.execute("ALTER TABLE sessions ADD COLUMN messages TEXT NOT NULL DEFAULT '[]'")
      rescue StandardError
        # Column already exists — safe to continue
      end

      # @param raw [String, Array, nil]
      # @return [Array]
      def parse_json_array(raw)
        case raw
        when Array then raw
        when String then JSON.parse(raw, symbolize_names: true)
        else []
        end
      rescue JSON::ParserError
        []
      end

      # @param raw [String, Hash, nil]
      # @return [Hash]
      def parse_json_hash(raw)
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
