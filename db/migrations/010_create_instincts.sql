CREATE TABLE IF NOT EXISTS instincts (
  id TEXT PRIMARY KEY,
  project_path TEXT NOT NULL,
  pattern TEXT NOT NULL,
  context_tags TEXT DEFAULT '[]',
  confidence REAL NOT NULL DEFAULT 0.5,
  decay_rate REAL NOT NULL DEFAULT 0.01,
  times_applied INTEGER NOT NULL DEFAULT 0,
  times_helpful INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_instincts_project ON instincts(project_path);
CREATE INDEX IF NOT EXISTS idx_instincts_confidence ON instincts(confidence DESC);
