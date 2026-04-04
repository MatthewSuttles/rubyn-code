# frozen_string_literal: true

# Expands the mailbox_messages CHECK constraint to include protocol message types:
#   shutdown_request, shutdown_response, status_change
#
# SQLite does not support ALTER CONSTRAINT, so we rebuild the table.
# The Migrator already wraps .up in a transaction — no manual BEGIN/COMMIT here.
module Migration012ExpandMailboxMessageTypes
  module_function

  def up(db) # rubocop:disable Metrics/MethodLength
    db.execute(<<~SQL)
      CREATE TABLE mailbox_messages_new (
        id TEXT PRIMARY KEY,
        sender TEXT NOT NULL,
        recipient TEXT NOT NULL,
        message_type TEXT NOT NULL DEFAULT 'message'
          CHECK(message_type IN ('message','task','result','error','broadcast','shutdown_request','shutdown_response','status_change')),
        payload TEXT NOT NULL,
        read INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
      )
    SQL

    db.execute(<<~SQL)
      INSERT INTO mailbox_messages_new (id, sender, recipient, message_type, payload, read, created_at)
      SELECT id, sender, recipient, message_type, payload, read, created_at
      FROM mailbox_messages
    SQL

    db.execute('DROP TABLE mailbox_messages')
    db.execute('ALTER TABLE mailbox_messages_new RENAME TO mailbox_messages')
    db.execute('CREATE INDEX IF NOT EXISTS idx_mailbox_recipient_read ON mailbox_messages(recipient, read)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_mailbox_sender ON mailbox_messages(sender)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_mailbox_created ON mailbox_messages(created_at)')
  end
end
