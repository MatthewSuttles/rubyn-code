# Layer 6: Sub-Agents

Isolated agents spawned for specific tasks, scoped to read-only or full access.

## Classes

- **`Runner`** — Spawns a sub-agent with its own fresh conversation context. Two types:
  `explore` (read-only tools) and `worker` (full write access). The sub-agent runs
  its own `Agent::Loop`, completes its task, and returns only a summary.

- **`Summarizer`** — Compresses a sub-agent's full conversation into a concise summary
  for the parent agent. Keeps the parent's context clean.
