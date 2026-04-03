# frozen_string_literal: true

require "json"
require "securerandom"

module RubynCode
  module Teams
    # JSONL-based mailbox for inter-agent messaging backed by SQLite.
    #
    # Messages are stored in the `mailbox_messages` table with structured
    # JSON content. Each message tracks read/unread state per recipient.
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
      # @return [String] the message id
      def send(from:, to:, content:, message_type: "message")
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

        @db.execute(
          <<~SQL,
            INSERT INTO mailbox_messages (id, sender, recipient, message_type, payload, read, created_at)
            VALUES (?, ?, ?, ?, ?, 0, ?)
          SQL
          [id, from, to, message_type, payload, now]
        )

        id
      end

      # Reads all unread messages for the given agent and marks them as read.
      #
      # @param name [String] the recipient agent name
      # @return [Array<Hash>] parsed message hashes
      def read_inbox(name)
        rows = @db.query(
          <<~SQL,
            SELECT id, payload FROM mailbox_messages
            WHERE recipient = ? AND read = 0
            ORDER BY created_at ASC
          SQL
          [name]
        ).to_a

        return [] if rows.empty?

        ids = rows.map { |r| r["id"] }
        messages = rows.map { |r| JSON.parse(r["payload"], symbolize_names: true) }

        # Mark all fetched messages as read in a single statement
        placeholders = ids.map { "?" }.join(", ")
        @db.execute(
          "UPDATE mailbox_messages SET read = 1 WHERE id IN (#{placeholders})",
          ids
        )

        messages
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
          send(from: from, to: recipient, content: content, message_type: "broadcast")
        end
      end

      # Returns the count of unread messages for the given agent.
      #
      # @param name [String] the recipient agent name
      # @return [Integer]
      def unread_count(name)
        rows = @db.query(
          "SELECT COUNT(*) AS cnt FROM mailbox_messages WHERE recipient = ? AND read = 0",
          [name]
        ).to_a
        rows.first&.fetch("cnt", 0) || 0
      end

      private

      # Creates the mailbox_messages table if it does not already exist.
      # Schema must stay in sync with db/migrations/009_create_teams.sql.
      def ensure_table!
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS mailbox_messages (
            id TEXT PRIMARY KEY,
            sender TEXT NOT NULL,
            recipient TEXT NOT NULL,
            message_type TEXT NOT NULL DEFAULT 'message'
              CHECK(message_type IN ('message','task','result','error','broadcast')),
            payload TEXT NOT NULL,
            read INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
          )
        SQL

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_mailbox_recipient_read
          ON mailbox_messages (recipient, read)
        SQL
      end
    end
  end
end
