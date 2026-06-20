# frozen_string_literal: true

require 'json'
require 'securerandom'

module RubynCode
  module Teams
    # JSONL-based mailbox for inter-agent messaging backed by SQLite.
    #
    # Messages are stored in the `mailbox_messages` table with structured
    # JSON content. Each message tracks read/unread state per recipient.
    # Supports structured data payloads and correlation IDs for
    # request/response tracking.
    class Mailbox
      # @param db [DB::Connection] the database connection
      def initialize(db)
        @db = db
        ensure_table!
      end

      # Sends a message from one agent to another.
      #
      # @param from [String] sender agent name
      # @param to [String] recipient agent name
      # @param content [String] message body
      # @param message_type [String] type of message (default: "message")
      # @param correlation_id [String, nil] optional correlation ID for request/response pairing
      # @param data [Hash, nil] optional structured data payload
      # @return [String] the message id
      # rubocop:disable Metrics/ParameterLists
      def send(from:, to:, content:, message_type: 'message', correlation_id: nil, data: nil)
        id = SecureRandom.uuid
        now = Time.now.utc.iso8601

        payload = JSON.generate({
                                  id: id,
                                  from: from,
                                  to: to,
                                  content: content,
                                  message_type: message_type,
                                  timestamp: now
                                })

        data_json = data ? JSON.generate(data) : nil

        @db.execute(
          <<~SQL,
            INSERT INTO mailbox_messages (id, sender, recipient, message_type, payload, correlation_id, data, read, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?)
          SQL
          [id, from, to, message_type, payload, correlation_id, data_json, now]
        )

        id
      end
      # rubocop:enable Metrics/ParameterLists

      # Sends a structured message with typed data payload.
      # Convenience wrapper around #send for machine-to-machine communication.
      #
      # @param from [String] sender agent name
      # @param to [String] recipient agent name
      # @param type [String] message type (e.g. 'task', 'result', 'error')
      # @param data [Hash] structured data payload
      # @param content [String] human-readable summary (default: auto-generated)
      # @param correlation_id [String, nil] optional correlation ID
      # @return [String] the message id
      # rubocop:disable Metrics/ParameterLists
      def send_structured(from:, to:, type:, data:, content: nil, correlation_id: nil)
        content ||= "#{type}: #{data.inspect}"[0, 200]
        correlation_id ||= SecureRandom.uuid

        send(
          from: from,
          to: to,
          content: content,
          message_type: type,
          correlation_id: correlation_id,
          data: data
        )
      end
      # rubocop:enable Metrics/ParameterLists

      # Reads all unread messages for the given agent and marks them as read.
      #
      # @param name [String] the recipient agent name
      # @return [Array<Hash>] parsed message hashes with optional :data key
      def read_inbox(name)
        rows = @db.query(
          <<~SQL,
            SELECT id, payload, correlation_id, data FROM mailbox_messages
            WHERE recipient = ? AND read = 0
            ORDER BY created_at ASC
          SQL
          [name]
        ).to_a

        return [] if rows.empty?

        ids = rows.map { |r| r['id'] }
        messages = rows.map { |r| parse_message_row(r) }

        # Mark all fetched messages as read in a single statement
        placeholders = ids.map { '?' }.join(', ')
        @db.execute(
          "UPDATE mailbox_messages SET read = 1 WHERE id IN (#{placeholders})",
          ids
        )

        messages
      end

      # Finds all messages matching a correlation ID.
      # Useful for tracking request/response chains.
      #
      # @param correlation_id [String] the correlation ID to search for
      # @return [Array<Hash>] matched messages ordered by creation time
      def find_by_correlation_id(correlation_id)
        rows = @db.query(
          <<~SQL,
            SELECT id, payload, correlation_id, data FROM mailbox_messages
            WHERE correlation_id = ?
            ORDER BY created_at ASC
          SQL
          [correlation_id]
        ).to_a

        rows.map { |r| parse_message_row(r) }
      end

      # Broadcasts a message from one agent to all other agents.
      #
      # @param from [String] sender agent name
      # @param content [String] message body
      # @param all_names [Array<String>] list of all agent names in the team
      # @return [Array<String>] message ids
      def broadcast(from:, content:, all_names:)
        recipients = all_names.reject { |n| n == from }

        recipients.map do |recipient|
          send(from: from, to: recipient, content: content, message_type: 'broadcast')
        end
      end

      # Returns unread messages for the given agent WITHOUT marking them as read.
      # Used by IdlePoller to check for pending work without consuming messages.
      #
      # @param name [String] the recipient agent name
      # @return [Array<Hash>] parsed message hashes
      def pending_for(name)
        rows = @db.query(
          <<~SQL,
            SELECT id, payload, correlation_id, data FROM mailbox_messages
            WHERE recipient = ? AND read = 0
            ORDER BY created_at ASC
          SQL
          [name]
        ).to_a

        rows.map { |r| parse_message_row(r) }
      end

      # Returns the count of unread messages for the given agent.
      #
      # @param name [String] the recipient agent name
      # @return [Integer]
      def unread_count(name)
        rows = @db.query(
          'SELECT COUNT(*) AS cnt FROM mailbox_messages WHERE recipient = ? AND read = 0',
          [name]
        ).to_a
        rows.first&.fetch('cnt', 0) || 0
      end

      private

      # Parses a message row into a hash, merging structured data if present.
      #
      # @param row [Hash] database row
      # @return [Hash] parsed message with optional :data and :correlation_id keys
      def parse_message_row(row)
        msg = JSON.parse(row['payload'], symbolize_names: true)
        msg[:correlation_id] = row['correlation_id'] if row['correlation_id']
        msg[:data] = JSON.parse(row['data'], symbolize_names: true) if row['data']
        msg
      rescue JSON::ParserError
        { content: row['payload'].to_s, parse_error: true }
      end

      # Creates the mailbox_messages table if it does not already exist.
      # Schema must stay in sync with db/migrations/009_create_teams.sql
      # and 014_multi_agent_upgrade.rb.
      def ensure_table!
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS mailbox_messages (
            id TEXT PRIMARY KEY,
            sender TEXT NOT NULL,
            recipient TEXT NOT NULL,
            message_type TEXT NOT NULL DEFAULT 'message'
              CHECK(message_type IN ('message','task','result','error','broadcast','shutdown_request','shutdown_response','status_change')),
            payload TEXT NOT NULL,
            correlation_id TEXT,
            data TEXT,
            read INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
          )
        SQL

        # Self-heal: add the columns the original migration lacked so
        # that test databases bootstrapped before the multi-agent
        # upgrade don't end up with a half-built table.  Each ALTER
        # is a no-op if the column already exists (SQLite returns an
        # error which we swallow).
        add_mailbox_column_if_missing('correlation_id')
        add_mailbox_column_if_missing('data')

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_mailbox_recipient_read
          ON mailbox_messages (recipient, read)
        SQL

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_mailbox_correlation
          ON mailbox_messages (correlation_id)
        SQL
      end

      # @return [Boolean] true if the column was added
      def add_mailbox_column_if_missing(column)
        @db.execute("ALTER TABLE mailbox_messages ADD COLUMN #{column} TEXT")
        true
      rescue SQLite3::SQLException
        false
      end
    end
  end
end
