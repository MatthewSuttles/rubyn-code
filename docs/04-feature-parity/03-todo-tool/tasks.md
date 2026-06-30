# 03 TodoWrite Live Checklist — Tasks

## Phase 0 — Scaffolding

- [x] Branch: `phase-04-todo-tool`

## Phase 1 — Store & Tool

- [x] `Tools::TodoStore` (MonitorMixin)
- [x] `replace` / `current` / `clear` / `empty?` / `render`
- [x] `Tools::TodoWrite` (registered in `Tools::Registry`)
- [x] Validate `status` ∈ {`pending`, `in_progress`, `completed`}
- [x] Validate non-empty `content`
- [x] Return formatted checklist on success; error string on invalid
- [x] `summarize` returns `checklist: N items`

## Phase 2 — Executor wiring

- [x] `Tools::Executor` `attr_accessor :todo_store`
- [x] `Tools::Executor#build_tool` injects `@store` via constructor
- [x] Autoload `TodoStore` and `TodoWrite` in `lib/rubyn_code.rb`

## Phase 3 — Loop ownership

- [x] `Agent::Loop#assign_optional_deps` constructs `TodoStore`
- [x] Wires `@tool_executor.todo_store`
- [x] `initialize_session!` clears the store per turn
- [x] `attr_reader :todo_store`

## Phase 4 — REPL surface

- [x] `CLI::REPL#handle_on_tool_result` calls `render_todo_checklist`
- [x] `CLI::REPL#render_todo_checklist` private method

## Phase 5 — Tests

- [x] `TodoStore` replace/clear/render/thread-safety
- [x] `TodoWrite` validation: status / symbol or string keys / fallback
- [x] `TodoWrite.summarize` pluralization

## Phase 6 — Lint & Ship

- [x] `bundle exec rubocop -A`
- [x] `bundle exec rspec` (16 examples, 0 failures)
- [x] Conventional commit
- [x] Push branch & open PR (#134)
- [x] PR squash-merged into main
