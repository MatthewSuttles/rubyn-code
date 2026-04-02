CREATE TABLE IF NOT EXISTS skills_cache (
  id TEXT PRIMARY KEY,
  skill_name TEXT NOT NULL UNIQUE,
  content_hash TEXT NOT NULL,
  loaded_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);

CREATE INDEX IF NOT EXISTS idx_skills_cache_name ON skills_cache(skill_name);
