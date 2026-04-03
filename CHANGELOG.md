# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Slash Command System** — Registry-based command dispatch replacing the REPL's monolithic
  `case` statement. 19 commands, each in its own file with full spec coverage.
  - `Commands::Base` abstract class, `Commands::Registry` for dispatch + tab-completion,
    `Commands::Context` (Data.define) for dependency injection
  - Commands return optional **action hashes** for REPL state changes
- **`/doctor`** — Environment health check: Ruby version, gems, database, API connectivity,
  skills, and project detection
- **`/tokens`** — Token estimation with `Data.define` stats object, context window percentage,
  and compaction threshold warning
- **`/plan`** — Plan mode toggle. When enabled, Agent::Loop sends no tools and injects a
  "reason, don't act" system prompt. Claude thinks out loud without executing.
- **`/context`** — Visual context window usage bar with color-coded fill (green → yellow → red)
- **`/diff`** — Quick git diff from the REPL (unstaged, staged, or vs a branch)
- **`/model`** — Show current model or switch between available Claude models
- **`/review`** — Trigger PR review against best practices with optional focus area
- **`/skill`** — Load a skill into conversation context or list all available skills
- **`/tasks`**, **`/spawn`**, **`/resume`**, **`/compact`**, **`/budget`**, **`/cost`**,
  **`/clear`**, **`/undo`**, **`/version`**, **`/help`**, **`/quit`** — Extracted from
  inline REPL handlers into individual command objects

### Changed
- `CLI::REPL` — Thin dispatcher, delegates all `/commands` to `Commands::Registry`
- `CLI::InputHandler` — Registry-driven classification, no more hardcoded command hash
- `Agent::Loop` — Plan mode support: skips tools and injects plan-mode system prompt

## [0.1.0] - 2025-01-01

### Added
- Initial release
- 16-layer architecture: Agent → Tools → Permissions → Context → Skills → SubAgents →
  Tasks → Background → Teams → Protocols → Autonomous → Memory → Observability →
  Hooks → MCP → Learning
- Claude API integration via OAuth or API key
- 30+ built-in tools
- SQLite persistence
- 112 curated skill documents
