# frozen_string_literal: true

# Multi-agent upgrade: adds parent-child tracking to teammates and
# structured messaging to mailbox_messages.
#
# Teammates: adds parent_agent_id column, fixes status CHECK
#   (DB had 'busy' but Ruby code uses 'active').
# Mailbox: adds correlation_id and data columns for structured messaging.
#
# Uses table-rebuild pattern because SQLite cannot ALTER CHECK constraints
# or ADD COLUMN with constraints reliably.
module Migration014MultiAgentUpgrade
  module_function

  def up(db)
    upgrade_teammates(db)
    upgrade_mailbox(db)
  end

  def upgrade_teammates(db)
    db.execute(<<~SQL)
      CREATE TABLE teammates_new (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        role TEXT NOT NULL,
        persona TEXT,
        model TEXT NOT NULL DEFAULT 'claude-sonnet-4-20250514',
        status TEXT NOT NULL DEFAULT 'idle' CHECK(status IN ('idle','active','offline')),
        parent_agent_id TEXT,
        metadata TEXT DEFAULT '{}',
        created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
      )
    SQL

    db.execute(<<~SQL)
      INSERT INTO teammates_new (id, name, role, persona, model, status, metadata, created_at)
      SELECT id, name, role, persona, model,
             CASE WHEN status = 'busy' THEN 'active' ELSE status END,
             metadata, created_at
      FROM teammates
    SQL

    db.execute('DROP TABLE teammates')
    db.execute('ALTER TABLE teammates_new RENAME TO teammates')
    db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_teammates_name ON teammates(name)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_teammates_status ON teammates(status)')
    db.execute('CREATE INDEX IF NOT EXISTS idx_teammates_parent ON teammates(parent_agent_id)')
  end

  def upgrade_mailbox(db)
    db.execute(<<~SQL)
      CREATE TABLE mailbox_messages_new (
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
    db.execute('CREATE INDEX IF NOT EXISTS idx_mailbox_correlation ON mailbox_messages(correlation_id)')
  end
end
