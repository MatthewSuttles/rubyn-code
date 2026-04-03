# Layer 7: Tasks

Task tracking with DAG-based dependency management.

## Classes

- **`Manager`** — CRUD operations for tasks. Persists to the `tasks` SQLite table.
  Supports status tracking, priority, ownership, and dependency resolution.

- **`DAG`** — Directed acyclic graph for task dependencies. Determines which tasks are
  ready to run (all dependencies met), detects cycles, and computes execution order.

- **`Models`** — Data objects for tasks and dependencies. Maps to/from SQLite rows.
