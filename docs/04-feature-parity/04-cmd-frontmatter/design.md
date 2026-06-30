# 04 Custom-Command Frontmatter — Design

## Overview

Extend `CustomLoader` to recognize frontmatter keys from
`~/.rubyn-code/commands/*.md` files:

| key             | type     | effect                                       |
|-----------------|----------|----------------------------------------------|
| `description`   | string   | existing — used by `/help`                  |
| `argument-hint` | string   | rendered inline next to the command name   |
| `allowed-tools` | string[] | restricts tool set (`with_allowed_tools`)    |
| `model`         | string   | one-shot override (`with_optional_model`)    |

Both hyphen and underscore spellings accepted.

## Architecture

```
~/.rubyn-code/commands/deploy.md
        │
        ▼
CustomLoader#build(path)
  ├── parse → meta, body
  ├── validate frontmatter helpers
  │     stringify(value)
  │     blank_to_nil(value)
  │     list_of_tools(value)
  └── CustomCommand.new(
        name:, description:, body:, source:,
        argument_hint:, allowed_tools:, model:
      )

CustomCommand#execute
  └── if restricts_tools? or overrides_model?
        wrap send_message in the Context hooks
      else send_message directly
```

## Pieces

### `CustomCommand`

```ruby
def initialize(name:, description:, body:,
               source: nil,
               argument_hint: nil,
               allowed_tools: nil,
               model: nil)

# help_label, restricts_tools?, overrides_model?
```

### `CustomLoader`

- `stringify(value)` — unwrap single-element arrays
- `blank_to_nil(value)` — empty string → nil
- `list_of_tools(value)` — comma-separated String or YAML array
- Lookup pattern: `meta['allowed_tools'] || meta['allowed-tools']`

### `Commands::Context` (Data.define)

```ruby
def with_allowed_tools(allowed = nil)
  apply_loop_override(:allowed_tools_override=, allowed) { yield }
end

def with_optional_model(model_name = nil)
  apply_loop_override(:model_override=, model_name) { yield }
end
```

`apply_loop_override` does set → yield → ensure-clear.

### `Agent::Loop` (gaps-closed in PR #138)

```ruby
def allowed_tools_override=(allowed)
  @allowed_tools_override = allowed.is_a?(Array) && !allowed.empty? ? allowed : nil
end

def model_override=(model_name)
  stripped = model_name.to_s.strip
  @model_override = stripped.empty? ? nil : stripped
end
```

`reset_iteration_state` clears them after the call.

`build_llm_opts` → `filtered_tool_definitions` honors the override;
`routed_model` returns `@model_override` before the fall-through.

## Out-of-scope

- Validation of model names in frontmatter
- Rejecting unknown tool names in `allowed-tools` at load time
- Block-level extra fields (`system-prompt:`, `mcp-servers:`)
- Per-prompt vs per-turn hooks for tool restrictions
