# Phase 1 — Chisel Core: Design

## Overview

One new module (`RubynCode::Chisel`) owns everything Chisel-specific: the list of
valid modes, how the active mode is resolved (env → config → default), and the
ruleset text per intensity. Two existing seams are touched: `Config` gains a
`chisel_mode` key, and `SystemPromptBuilder` calls into `Chisel` for its prompt
section. A new `/chisel` command reads/writes the config key.

**Design principles:** vertical slice (config → prompt → command, end-to-end),
SRP (the module is the single source of truth for modes and text), KISS (ruleset
is a constant, not a templating system; no new persistence layer).

## Architecture

### `RubynCode::Chisel` (new module — `lib/rubyn_code/chisel.rb`)

```ruby
Chisel::MODES            # => %w[off lite full ultra]
Chisel.mode              # -> "off" | "lite" | "full" | "ultra"  (resolved, validated)
Chisel.enabled?          # -> mode != "off"
Chisel.valid?(str)       # -> Boolean
Chisel.prompt_section    # -> String ("" when off)  — what SystemPromptBuilder injects
```

**Responsibility:** be the single source of truth for what modes exist, which one
is active, and what text each one injects.
**Collaborators:** reads `Config::Settings` for the persisted value; reads
`ENV['RUBYN_CHISEL_MODE']` for the override. No writes (the command writes).
**Why a module, not inline?** Three callers need the same mode-resolution and
text — the prompt builder (Phase 1), and the review/audit commands (Phase 2)
which key their analysis off the same ladder. Centralizing avoids drift.

Mode resolution order, with invalid values falling back to `off`:

```
ENV['RUBYN_CHISEL_MODE'] (if valid) → config chisel_mode (if valid) → "off"
```

The ruleset is a frozen heredoc constant. `prompt_section` assembles: header +
ladder (all modes) + intensity addendum (full/ultra) + safety floor (all modes).

### `Config` changes

- `Defaults::CHISEL_MODE = 'off'`
- Add `:chisel_mode` to `Settings::CONFIGURABLE_KEYS` and `DEFAULT_MAP` so the
  generated accessor + `get('chisel_mode')` resolve the default cleanly.
- Add a `chisel_mode` property to `config/schema.json` with
  `enum: [off, lite, full, ultra]` so `/config`-style validation is friendly.
  (`additionalProperties: true` already accepts it; the enum just improves error
  messages.)

### `SystemPromptBuilder` change

`build_static_prompt_sections` gains one call:

```ruby
def build_static_prompt_sections
  parts = []
  # ...existing appends...
  append_chisel_ruleset(parts)
  append_deferred_tools(parts)
  parts.join("\n")
end

def append_chisel_ruleset(parts)
  section = Chisel.prompt_section
  parts << section unless section.empty?
rescue StandardError
  nil   # never let Chisel break the prompt
end
```

It lives in the **static** sections (memoized once per user turn), so resolving
the mode costs one `Settings.new` per turn, matching how `/model` reads config.

### `/chisel` command (`lib/rubyn_code/cli/commands/chisel.rb`)

```ruby
class Chisel < Base
  def self.command_name = '/chisel'
  def self.description = 'Set or show Chisel intensity (off|lite|full|ultra)'
  def execute(args, ctx)  # no arg → report; valid arg → persist+confirm; bad arg → warn
end
```

Writes via `Config::Settings.new.tap { |s| s.set('chisel_mode', mode); s.save! }`.
Registered in `repl_commands.rb`'s built-in list. Naming note: the command class
`Commands::Chisel` and the engine `RubynCode::Chisel` share a base name but live
in different namespaces — no collision.

## Test strategy

- **Unit (`spec/.../chisel_spec.rb`):** mode resolution precedence (env > config >
  default); invalid values fall back to `off`; `enabled?`; `prompt_section` is
  `""` when off, contains the safety floor in every non-off mode, and nests
  (lite ⊂ full ⊂ ultra).
- **Unit (`spec/.../config/settings_spec.rb` addition):** `chisel_mode` defaults
  to `off`; round-trips through `save!`/`load!`.
- **Unit (`spec/.../cli/commands/chisel_spec.rb`):** no-arg reports; valid arg
  persists; invalid arg warns and does not change config (use a tmp config path).
- **Integration:** a `SystemPromptBuilder` example asserting the ruleset appears
  when mode is on and is absent when off. Tested through `build_system_prompt`'s
  observable output, not private internals where avoidable.

Tests set `RUBYN_TESTING=1` (already global) so `Settings` uses a tmp config and
never touches the developer's real `~/.rubyn-code/config.yml`.

## Migration / rollout

No migration. New key defaults to `off`, so existing users see no change until
they opt in. Rollback = revert the PR; the orphaned `chisel_mode:` line in a
user's config is inert (unknown keys are accepted).

## Future enhancements

- Per-project mode override (`.rubyn-code/config.yml`) — deferred.
- Phase 2 will add `Chisel.ladder_text` reuse for the review/audit prompts.
