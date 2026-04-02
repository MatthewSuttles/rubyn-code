CREATE TABLE IF NOT EXISTS memories (
  id TEXT PRIMARY KEY,
  project_path TEXT NOT NULL,
  tier TEXT NOT NULL CHECK(tier IN ('short','medium','long')),
  category TEXT,
  content TEXT NOT NULL,
  relevance_score REAL NOT NULL DEFAULT 1.0,
  access_count INTEGER NOT NULL DEFAULT 0,
  last_accessed_at TEXT,
  expires_at TEXT,
  metadata TEXT DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_memories_project ON memories(project_path);
CREATE INDEX IF NOT EXISTS idx_memories_tier ON memories(tier);
CREATE INDEX IF NOT EXISTS idx_memories_category ON memories(project_path, category);
CREATE INDEX IF NOT EXISTS idx_memories_expires ON memories(expires_at);

CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
  content,
  category,
  content=memories,
  content_rowid=rowid,
  tokenize='porter unicode61'
);

-- Triggers to keep FTS index in sync with the memories table
CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
  INSERT INTO memories_fts(rowid, content, category)
  VALUES (NEW.rowid, NEW.content, NEW.category);
END;

CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, content, category)
  VALUES ('delete', OLD.rowid, OLD.content, OLD.category);
END;

CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
  INSERT INTO memories_fts(memories_fts, rowid, content, category)
  VALUES ('delete', OLD.rowid, OLD.content, OLD.category);
  INSERT INTO memories_fts(rowid, content, category)
  VALUES (NEW.rowid, NEW.content, NEW.category);
END;
