# Layer 16: Learning

Continuous learning from session patterns with confidence decay.

## Classes

- **`Extractor`** — Post-session analysis using a cheaper LLM (Haiku). Scans the last 30
  messages for patterns: error resolutions, user corrections, workarounds, debugging
  techniques, project-specific conventions. Persists as instincts.

- **`Instinct`** — A learned pattern with a confidence score that decays over time.
  Stored in the `instincts` SQLite table. Higher confidence = more likely to be injected
  into future prompts.

- **`Injector`** — Selects relevant instincts (confidence >= 0.3, max 10) and injects
  them into the system prompt for the current session. Filters by project context.
