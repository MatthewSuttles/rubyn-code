# Layer 3: Permissions

Tiered permission system controlling which tools the agent can use.

## Classes

- **`Tier`** — Defines permission tiers (e.g. `:readonly`, `:edit`, `:admin`).
  Each tier grants access to a set of tools. Higher tiers include all lower-tier tools.

- **`Policy`** — Evaluates whether a tool call is allowed given the current tier.
  Consulted by `Tools::Executor` before every tool invocation.

- **`DenyList`** — Explicit tool deny list. Overrides tier permissions.
  Configurable per-project via `.rubyn-code.yml`.

- **`Prompter`** — Asks the user for permission when a tool requires escalation.
  Renders the tool name and arguments, waits for yes/no confirmation.
