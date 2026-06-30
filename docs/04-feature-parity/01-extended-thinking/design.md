# 01 Extended Thinking — Design

## Overview

Plumb a per-session reasoning budget through the LLM layer and the REPL so
that the model can spend dedicated tokens deliberating before producing an
answer. Implemented as a tiny additive surface — `thinking: {budget_tokens: N}`
on the adapter, a `thinking_budget_tokens` config key, and a `/think` slash
command for live toggling.

## Architecture

```
/think <budget>  ──►  rubyn_code_cli.repl
                          │
                          ▼
                       llm_client.thinking_budget_tokens = N   (instance state)
                          │
                          ▼
                       llm_client.chat(messages:, thinking: {...})
                          │
                          ▼
                       adapters/anthropic
                                            │
                                            ▼
                                     build_request_body
                                          ├── injects  thinking: {type: 'enabled', budget_tokens}
                                          └── ensures  max_tokens ≥ budget + 1024
```

## Pieces

### `LLM::ThinkingBlock` (message_builder.rb)

`Data.define(:text)` content block. The API contract for both Anthropic and
OpenAI stays unchanged — the rest just treats it as opaque data when not
used.

### `MessageBuilder#format_messages`

The `ThinkingBlock` branch emits `{ type: 'thinking', text: block.text }`
— the same shape Anthropic returns on the wire.

### `Adapters::Anthropic#build_request_body`

```ruby
def apply_thinking(body, thinking)
  return unless thinking.is_a?(Hash) && thinking[:budget_tokens].to_i.positive?
  body[:thinking] = { type: 'enabled', budget_tokens: thinking[:budget_tokens].to_i }
end

def ensure_max_tokens_for_thinking(max_tokens, thinking)
  # Anthropic requires max_tokens > budget_tokens.
  # Bump up to budget + 1024 if not already large enough.
end
```

### `Adapters::AnthropicStreaming`

Tracks `@current_thinking_text` and emits a `ThinkingBlock` content block
when the stream closes a thinking-type block. `on_text` callbacks receive
a `thinking_delta` event so the REPL could render the deliberation live
(out of scope for this PR but the hook is in place).

### `LLM::Client`

```ruby
def chat(messages:, tools: nil, system: nil, model: nil, **opts)
  kwargs[:thinking] = effective_thinking if effective_thinking
  @adapter.chat(**kwargs)
end

def current_thinking_hash
  budget = @thinking_budget_tokens.to_i
  return nil unless budget.positive?
  { budget_tokens: budget }
end
```

The client reads its own `thinking_budget_tokens` state when no
explicit thinking hash was passed.

### `/think` slash command

```
/think              # show current budget
/think off | 0      # disable
/think <budget>     # enable with <budget> tokens
```

Stored on the LLM::Client instance and surfaced as `attr_accessor`.
The REPL hydrates it from settings at startup.

### Config

New key `thinking_budget_tokens`:
- `Config::Defaults::THINKING_BUDGET_TOKENS = 0`
- `Config::Settings::CONFIGURABLE_KEYS` + `DEFAULT_MAP` entries
- `Config::Validator` schema entry: integer, 0–200000

## Out of scope

- Persisting `/think` state across REPL launches (use the config key).
- Caching thinking_blocks as a prompt-cache breakpoint.
- Renderer hook for live-streaming thinking tokens (the
  `thinking_delta` event is emitted but no UI subscribes yet).
- Multi-turn thinking-signature replay (Anthropic returns a `signature`
  field we don't yet capture or send back).
