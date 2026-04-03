# Layer 13: Observability

Token counting, cost tracking, and budget enforcement.

## Classes

- **`TokenCounter`** — Estimates token counts for messages and tool results.
  Used by `Context::Manager` for compaction decisions and by `CostCalculator` for pricing.

- **`CostCalculator`** — Computes cost per API call based on model, input/output tokens.
  Persists records to the `cost_records` table.

- **`BudgetEnforcer`** — Enforces per-session and global budget caps. Raises
  `BudgetExceededError` when the limit is hit. Checked in `Agent::Loop` before each API call.

- **`UsageReporter`** — Generates usage summaries: tokens used, cost breakdown, session stats.
  Powers the `/cost` and `/budget` slash commands.

- **`Models`** — Data objects for cost records.
