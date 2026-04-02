CREATE TABLE IF NOT EXISTS hook_configs (
  id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  handler_type TEXT NOT NULL,
  handler_config TEXT NOT NULL DEFAULT '{}',
  enabled INTEGER NOT NULL DEFAULT 1,
  priority INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_hooks_event ON hook_configs(event_type);
CREATE INDEX IF NOT EXISTS idx_hooks_enabled ON hook_configs(enabled, event_type);
