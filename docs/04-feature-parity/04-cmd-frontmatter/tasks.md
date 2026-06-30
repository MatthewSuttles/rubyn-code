# 04 Custom-Command Frontmatter — Tasks

## Phase 0 — Scaffolding

- [x] Branch: `phase-04-cmd-frontmatter`

## Phase 1 — Parser & helpers

- [x] `CustomLoader#stringify` (YAML scalar → String, array-unwrap)
- [x] `CustomLoader#blank_to_nil`
- [x] `CustomLoader#list_of_tools`
- [x] `parse` returns `(meta, body)`
- [x] `build` accepts `argument_hint:`, `allowed_tools:`, `model:`

## Phase 2 — CustomCommand surface

- [x] New constructor kwargs
- [x] New attr_readers
- [x] `#help_label`, `#restricts_tools?`, `#overrides_model?`
- [x] `#execute` wraps `send_message` in Context hooks when set

## Phase 3 — Context seams

- [x] `Commands::Context#with_allowed_tools`
- [x] `Commands::Context#with_optional_model`
- [x] `apply_loop_override` private helper

## Phase 4 — Tests

- [x] Hyphen & underscore spellings
- [x] `allowed-tools` as comma string and YAML array
- [x] `model` extraction
- [x] Blank values coerce to nil
- [x] `#help_label` with and without hint
- [x] `#execute` invokes wrappers

## Phase 5 — Lint & Ship

- [x] `bundle exec rubocop -A`
- [x] `bundle exec rspec` (17 examples, 0 failures)
- [x] Conventional commit
- [x] Push branch & open PR (#135)
- [x] PR squash-merged into main

## Phase 6 — Audit-discovered sub-gaps

- [x] **PR #138** — `Agent::Loop#allowed_tools_override=` /
      `#model_override=` enforce frontmatter; existing no-op
      hooks now drive the loop. (9 examples in
      `spec/rubyn_code/agent/loop_overrides_spec.rb`)
