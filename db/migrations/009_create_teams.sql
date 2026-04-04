CREATE TABLE IF NOT EXISTS teammates (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL,
  persona TEXT,
  model TEXT NOT NULL DEFAULT 'claude-sonnet-4-20250514',
  status TEXT NOT NULL DEFAULT 'idle' CHECK(status IN ('idle','busy','offline')),
  metadata TEXT DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_teammates_name ON teammates(name);
CREATE INDEX IF NOT EXISTS idx_teammates_status ON teammates(status);

CREATE TABLE IF NOT EXISTS mailbox_messages (
  id TEXT PRIMARY KEY,
  sender TEXT NOT NULL,
  recipient TEXT NOT NULL,
  message_type TEXT NOT NULL DEFAULT 'message' CHECK(message_type IN ('message','task','result','error','broadcast','shutdown_request','shutdown_response','status_change')),
  payload TEXT NOT NULL,
  read INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_mailbox_recipient_read ON mailbox_messages(recipient, read);
CREATE INDEX IF NOT EXISTS idx_mailbox_sender ON mailbox_messages(sender);
CREATE INDEX IF NOT EXISTS idx_mailbox_created ON mailbox_messages(created_at);
