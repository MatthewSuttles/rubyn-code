# Config Layer

Application settings with per-project overrides.

## Classes

- **`Settings`** — Main configuration module. Merges defaults with user overrides from
  `~/.rubyn-code/config.yml` and project-level `.rubyn-code.yml`.

- **`Defaults`** — Frozen constants for all default values: `MAX_ITERATIONS`, model names,
  token limits, budget caps, permission tiers, etc.

- **`ProjectConfig`** — Loads project-specific configuration from `.rubyn-code.yml` in the
  working directory. Supports custom permission tiers, deny lists, and hook definitions.
