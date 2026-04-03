# Layer 12: Memory

Persistent cross-session memory backed by SQLite.

## Classes

- **`Store`** — Writes memories to the `memories` table. Each memory has content, category
  (`code_pattern`, `user_preference`, `project_convention`, `error_resolution`, `decision`),
  and a retention tier (`short`, `medium`, `long`).

- **`Search`** — Full-text search across memories. Filters by category and tier.
  Used by the agent to recall context from previous sessions.

- **`SessionPersistence`** — Saves and restores session state (conversation, tasks, costs)
  across REPL sessions. Keyed by session ID in the `sessions` table.

- **`Models`** — Data objects mapping to/from SQLite memory rows.
