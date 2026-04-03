# Layer 4: Context Management

Manages the conversation context window to stay within Claude's token limits.

## Classes

- **`Manager`** — Orchestrates context strategy. Tracks token usage, decides when
  compaction is needed, selects the right compaction strategy.

- **`Compactor`** — Base compaction logic. Sends the conversation to Claude with a
  summarization prompt, replaces old messages with the summary.

- **`AutoCompact`** — Triggers automatically when token usage exceeds a threshold
  (e.g. 80% of the context window). Runs transparently mid-conversation.

- **`MicroCompact`** — Lightweight compaction that trims tool results (large file
  contents, long bash outputs) without summarizing the whole conversation.

- **`ManualCompact`** — Triggered by the user via `/compact`. Lets you specify a
  focus area for the summary (e.g. "focus on the auth refactor").
