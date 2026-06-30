# Phase 4 — Claude Code Feature Parity: Design

## Overview

Six additive feature gaps that bring rubyn-code to closer parity with
Claude Code's interactive UX. Each ships as its own PR, off-by-default,
with full specs and per-feature docs at `docs/04-feature-parity/NN-slug/`.

## Architecture

The six features occupy five distinct layers:

| Gap | Layer |
|-----|-------|
| 1: extended thinking   | `LLM::*` and `CLI::Commands::Think` |
| 2: image input         | `LLM::MessageBuilder`, `LLM::ImageReader`, `CLI::MentionExpander`, all adapters |
| 3: TodoWrite           | `Tools::TodoWrite`, `Tools::TodoStore`, `Agent::Loop`, `CLI::REPL#render_todo_checklist` |
| 4: frontmatter         | `CLI::Commands::CustomLoader`, `CustomCommand`, `Agent::Loop` overrides, `Commands::Context` |
| 5: .mcp.json discovery | `MCP::Discovery`, `REPL#setup_mcp_servers!`, `CLI::Commands::Mcp` |
| 6: /export             | `CLI::Commands::Export` |

All six preserve existing public behavior — every change is additive.
Backwards-compatible:

- `MessageBuilder` accepts the existing message shapes plus `ThinkingBlock`
  and `ImageBlock` data types.
- `Agent::Loop#send_message` gains an optional `blocks:` kwarg; the
  existing one-arg signature is preserved.
- `Conversation#add_user_message` already accepted String OR Array content;
  image turns use the Array shape.
- `Tools::Executor` gains a `todo_store` accessor; tools that don't accept
  `store:` are unaffected.
- `REPL#setup_mcp_servers!` swaps from `MCP::Config.load` to
  `MCP::Discovery.discover`. Output semantics are equivalent (with the
  addition of `[project]` / `[user]` source tags).
- `LLM::Client#chat` accepts `thinking:`; omitted → no behavior change.

## Pattern: per-prompt override ↔ Agent::Loop snapshot

Gaps 4 (allowed-tools / model) and the gap-5 wiring both rely on a
small pattern: a one-shot override on the loop that is read once in
`build_llm_opts` / `routed_model` and cleared in `reset_iteration_state`.
`Commands::Context#with_allowed_tools` / `#with_optional_model` wrap a
block to set + clear the override safely with `ensure`.

```ruby
def with_optional_model(model_name = nil)
  apply_loop_override(:model_override=, model_name) { yield }
end

def apply_loop_override(method, value)
  loop = agent_loop
  return yield unless loop.respond_to?(method)
  loop.public_send(method, value)
  yield
ensure
  loop&.public_send(method, nil) if loop&.respond_to?(method)
end
```

## Pattern: shared checklist via dependency injection

Gap 3 uses a `MonitorMixin`-protected `Tools::TodoStore` shared by
reference between:

- `Agent::Loop` (owns the instance and exposes it via `attr_reader`)
- `Tools::TodoWrite` (mutates it on each call)
- `CLI::REPL` (renders the current state via `render_todo_checklist`)

`Tools::Executor#build_tool` detects tools whose `initialize` accepts
`store:` and `instance_variable_set`s it, mirroring the existing
`ide_client:` injection.

## Pattern: chat-level capability flags

Gap 1 establishes a "request capability flag" pattern: pieces of the
LLM interface that are conditional (thinking, tools) are added as kwarg
fields to the adapter chat signature. A non-zero value triggers the
adapter-specific translation; a nil/zero is silently ignored. Keeping
the adapter signature stable across providers and across enabled/disabled
configurations minimizes branch churn in callers.

## Out of scope (across the six gaps)

- OAuth flow for HTTP/SSE MCP transports (deferred per Gap 5 plan)
- Cross-session persistence of `/think` state
- Per-task subtasks in TodoWrite
- Custom-command model validation in frontmatter
- Markdown / JSONL import for `/export`
- Multi-turn thinking-signature replay (Anthropic's `signature` field
  passed back in subsequent turns)

## Audit-discovered sub-gaps closed during execution

| PR | Sub-gap |
|---|---------|
| #138 | `allowed-tools` / `model` were parsed but had no-op Context hooks. Now actually drive `Agent::Loop`. |
| #139 | `/mcp` read only user-level config; now reads `MCP::Discovery.discover`. |
| #140 | `ImageReader` had no autoload for `ImageBlock`; cold REPL could NameError. Fixed. |
| #141 | `LLM::ThinkingBlock` had no autoload entry; `ImageReader` didn't require `base64`. Cold REPL could crash. Fixed; smoke + WebMock wireformat tests added. |
