# frozen_string_literal: true

require 'securerandom'
require 'json'

module RubynCode
  module Memory
    # Saves and restores full conversation sessions to SQLite, enabling
    # session continuity across process restarts and session browsing.
    class SessionPersistence # rubocop:disable Metrics/ClassLength -- session CRUD + incremental message journal
      # @param db [DB::Connection] database connection
      def initialize(db)
        @db = db
        # Per-session journal bookkeeping: how many messages are already
        # persisted and their object identities, so append-only saves can be
        # detected without comparing message contents.
        @journal_state = {}
        ensure_table
      end

      # Persists a complete session snapshot.
      #
      # Hot-path friendly: when the messages array has only grown since the
      # last save for this session, the new messages are appended to the
      # messages journal table instead of rewriting the whole JSON blob.
      # The blob is only rewritten when history was replaced (compaction,
      # undo, resume) or on the first save of a process.
      #
      # @param attrs [Hash] session attributes:
      #   :session_id, :project_path, :messages (required);
      #   :title, :model, :metadata (optional)
      # @return [void]
      def save_session(session_id:, project_path:, messages:, **opts)
        if appendable?(session_id, messages)
          append_to_journal(session_id, messages, opts)
        else
          snapshot_session(session_id, project_path, messages, opts)
        end
        remember_journal_state(session_id, messages)
      rescue StandardError
        # Journal append can fail (e.g. role CHECK constraint on legacy
        # schemas) — fall back to a full snapshot.
        snapshot_session(session_id, project_path, messages, opts)
        remember_journal_state(session_id, messages)
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
        blob_messages = parse_json_array(row['messages'])
        blob_messages += journal_messages(session_id) if blob_messages.is_a?(Array)
        {
          messages: blob_messages,
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
        where_clause, params = build_list_filters(project_path, status)
        params << limit

        rows = @db.query(<<~SQL, params).to_a
          SELECT id, project_path, title, model, status, metadata, created_at, updated_at
          FROM sessions
          #{where_clause}
          ORDER BY updated_at DESC
          LIMIT ?
        SQL

        rows.map { |row| row_to_session_summary(row) }
      end

      # Updates session attributes.
      #
      # @param session_id [String]
      # @param attrs [Hash] attributes to update (:title, :status, :model, :metadata, :messages)
      # @return [void]
      def update_session(session_id, **attrs)
        return if attrs.empty?

        sets, params = build_update_clauses(attrs)
        return if sets.empty?

        sets << 'updated_at = ?'
        params << Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
        params << session_id

        @db.execute("UPDATE sessions SET #{sets.join(', ')} WHERE id = ?", params)
        clear_journal(session_id) if attrs.key?(:messages)
      end

      # Deletes a session permanently.
      #
      # @param session_id [String]
      # @return [void]
      def delete_session(session_id)
        clear_journal(session_id)
        @db.execute('DELETE FROM sessions WHERE id = ?', [session_id])
      end

      JSON_ATTRS = %i[metadata messages].freeze
      SIMPLE_ATTRS = %i[title status model].freeze

      private

      # ── Incremental persistence ───────────────────────────────────────

      # True when this process has already persisted a prefix of +messages+
      # for the session and the prefix is unchanged, so only the tail needs
      # to be written. Compares object identities — compaction/undo/resume
      # replace message objects, which forces a snapshot.
      def appendable?(session_id, messages)
        state = @journal_state[session_id]
        return false unless state
        return false if messages.size < state[:count]

        messages.first(state[:count]).map(&:object_id) == state[:ids]
      end

      def remember_journal_state(session_id, messages)
        @journal_state[session_id] = {
          count: messages.size,
          ids: messages.map(&:object_id)
        }
      end

      # Appends the not-yet-persisted tail of +messages+ to the journal
      # table and touches the session row.
      def append_to_journal(session_id, messages, opts)
        new_messages = messages[@journal_state[session_id][:count]..] || []
        now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')

        @db.transaction do
          new_messages.each do |msg|
            @db.execute(
              'INSERT INTO messages (session_id, role, content, created_at) VALUES (?, ?, ?, ?)',
              [session_id, msg[:role] || msg['role'], JSON.generate(msg), now]
            )
          end
          touch_session(session_id, opts, now)
        end
      end

      def touch_session(session_id, opts, now)
        meta_json = opts.key?(:metadata) ? JSON.generate(opts[:metadata]) : nil
        @db.execute(<<~SQL, [opts[:title], opts[:model], meta_json, now, session_id])
          UPDATE sessions SET
            title = COALESCE(?, title),
            model = COALESCE(?, model),
            metadata = COALESCE(?, metadata),
            updated_at = ?
          WHERE id = ?
        SQL
      end

      # Writes the full messages blob and clears any journaled tail —
      # the blob becomes the single source of truth again.
      def snapshot_session(session_id, project_path, messages, opts)
        now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
        messages_json = JSON.generate(messages)
        meta_json = JSON.generate(opts.fetch(:metadata, {}))
        title = opts[:title]
        model = opts[:model]

        insert_params = [session_id, project_path, title, model, messages_json, 'active', meta_json, now, now]
        update_params = [messages_json, title, model, meta_json, now]

        @db.transaction do
          @db.execute(<<~SQL, insert_params + update_params)
            INSERT INTO sessions (id, project_path, title, model, messages, status, metadata, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              messages = ?,
              title = COALESCE(?, title),
              model = COALESCE(?, model),
              metadata = ?,
              updated_at = ?
          SQL
          @db.execute('DELETE FROM messages WHERE session_id = ?', [session_id])
        end
      end

      # Journaled messages appended after the last blob snapshot, in insert order.
      def journal_messages(session_id)
        rows = @db.query(
          'SELECT content FROM messages WHERE session_id = ? ORDER BY id',
          [session_id]
        ).to_a
        rows.filter_map { |row| parse_journal_row(row['content']) }
      rescue StandardError
        []
      end

      def parse_journal_row(raw)
        return nil unless raw.is_a?(String)

        JSON.parse(raw, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end

      def clear_journal(session_id)
        @journal_state.delete(session_id)
        @db.execute('DELETE FROM messages WHERE session_id = ?', [session_id])
      rescue StandardError
        nil
      end

      def build_list_filters(project_path, status)
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
        [where_clause, params]
      end

      def row_to_session_summary(row)
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

      def build_update_clauses(attrs)
        sets = []
        params = []

        attrs.each do |key, value|
          next unless SIMPLE_ATTRS.include?(key) || JSON_ATTRS.include?(key)

          sets << "#{key} = ?"
          params << (JSON_ATTRS.include?(key) ? JSON.generate(value) : value)
        end

        [sets, params]
      end

      def ensure_table
        ensure_sessions_table
        ensure_messages_table
      end

      def ensure_sessions_table
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

      # Journal table for incrementally persisted messages. Mirrors
      # db/migrations/002_create_messages.sql for databases that predate it.
      def ensure_messages_table
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
            role TEXT NOT NULL CHECK(role IN ('system','user','assistant','tool','function')),
            content TEXT,
            tool_calls TEXT,
            tool_use_id TEXT,
            tool_name TEXT,
            token_count INTEGER,
            is_compacted INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
          )
        SQL
        @db.execute('CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(session_id)')
      rescue StandardError
        # Table creation is best-effort — save_session falls back to
        # full snapshots when the journal is unavailable.
        nil
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
