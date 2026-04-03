# Layer 14: Hooks

Event hooks for extending agent behavior.

## Classes

- **`Registry`** — Stores hook definitions keyed by event name. Events include
  `before_tool`, `after_tool`, `before_llm`, `after_llm`, `on_error`, etc.

- **`Runner`** — Executes registered hooks when events fire. Hooks run synchronously
  in registration order. A hook can modify or abort the event.

- **`BuiltIn`** — Default hooks shipped with the gem: logging, cost tracking,
  context auto-compaction triggers.

- **`UserHooks`** — Loads user-defined hooks from `~/.rubyn-code/hooks/` or
  project-level `.rubyn-code/hooks/`. Ruby files that register via the `Registry`.
