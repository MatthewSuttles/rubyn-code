# 01 Extended Thinking — Tasks

## Phase 0 — Scaffolding

- [x] Branch: `phase-04-extended-thinking`

## Phase 1 — Message builder / adapter layer

- [x] `LLM::ThinkingBlock` (`Data.define(:text)`)
- [x] `MessageBuilder#format_content_blocks` branch for ThinkingBlock
- [x] Plumb `thinking:` kwarg through `LLM::Client#chat`
- [x] Update `Adapters::Base#chat` signature
- [x] `Adapters::Anthropic#chat` forwards `thinking:`
- [x] `apply_thinking` + `ensure_max_tokens_for_thinking` helpers
- [x] `parse_content_blocks` branch for `thinking` blocks
- [x] `thinking_delta` support in `AnthropicStreaming`
- [x] Thinking content stored in `ThinkingBlock` per stream slot

## Phase 2 — REPL surface

- [x] `thinking_budget_tokens` in Config (Defaults / Settings / schema)
- [x] `attr_accessor :thinking_budget_tokens` on `LLM::Client`
- [x] `current_thinking_hash` helper (nil when ≤ 0)
- [x] REPL hydrates budget at startup
- [x] `Commands::Think` slash command (`/think <budget>` / `off`)
- [x] Registered in `cli/repl_commands.rb` and `lib/rubyn_code.rb`

## Phase 3 — Tests

- [x] `LLM::ThinkingBlock` Data API
- [x] `MessageBuilder#format_messages` round-trip
- [x] Anthropic adapter helpers (`apply_thinking`, `ensure_max_tokens_for_thinking`)
- [x] Anthropic adapter `parse_content_blocks` for thinking blocks
- [x] AnthropicStreaming SSE → ThinkingBlock
- [x] `LLM::Client` forwards / omits the `thinking` kwarg
- [x] `Commands::Think` toggle / parser branches
- [x] `repl_spec.rb` mocks updated for new attribute

## Phase 4 — Lint & Ship

- [x] `bundle exec rubocop -A` over touched files
- [x] `bundle exec rspec` over the touched specs (66 examples, 0 failures)
- [x] Conventional commit
- [x] Push branch & open PR (#132)
- [x] PR squash-merged into main
