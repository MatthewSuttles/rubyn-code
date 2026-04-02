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
  from_agent TEXT NOT NULL,
  to_agent TEXT NOT NULL,
  content TEXT NOT NULL,
  message_type TEXT NOT NULL DEFAULT 'text' CHECK(message_type IN ('text','task','result','error')),
  read INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_mailbox_to ON mailbox_messages(to_agent, read);
CREATE INDEX IF NOT EXISTS idx_mailbox_from ON mailbox_messages(from_agent);
CREATE INDEX IF NOT EXISTS idx_mailbox_created ON mailbox_messages(created_at);
