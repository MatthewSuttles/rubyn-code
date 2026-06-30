# 05 `.mcp.json` Auto-Discovery — Tasks

## Phase 0 — Scaffolding

- [x] Branch: `phase-04-mcp-discovery`

## Phase 1 — Discovery module

- [x] `lib/rubyn_code/mcp/discovery.rb`
- [x] `Entry` Data.define
- [x] `discover(project_root)`
- [x] `load_project(project_root)` with three rescue branches
- [x] `build_entry` (skips invalid entries with Debug.warn)
- [x] `to_entry` adapter from MCP::Config
- [x] `stdio_servers` / `remote_servers` classifiers
- [x] Autoload in `lib/rubyn_code.rb`

## Phase 2 — Tests

- [x] `discover` returns `[]` for missing project_root
- [x] stdio entry round-trip
- [x] URL entry round-trip
- [x] Skips entries with neither command nor url
- [x] Malformed JSON does NOT raise
- [x] stdio vs remote classification
- [x] User + project entries coexist with source tagging

## Phase 3 — Lint & Ship

- [x] `bundle exec rubocop -A`
- [x] `bundle exec rspec` (8 examples, 0 failures)
- [x] Conventional commit
- [x] Push branch & open PR (#136)
- [x] PR squash-merged into main

## Phase 4 — Audit-discovered sub-gaps

- [x] **PR #138** — `REPL#setup_mcp_servers!` switched from
      `MCP::Config.load` to `MCP::Discovery.discover` so project
      `.mcp.json` entries actually flow through
- [x] **PR #139** — `/mcp` command uses `Discovery.discover` and
      prefixes each entry with `[project]` / `[user]`. (3 examples in
      `spec/rubyn_code/cli/commands/mcp_spec.rb`)