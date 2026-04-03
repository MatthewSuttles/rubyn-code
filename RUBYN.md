# RUBYN.md — Rubyn Code

> Auto-loaded into agent context when working in this directory.

## What Is This?

`rubyn-code` (v0.1.0) — an AI-powered CLI coding assistant for Ruby and Rails.
Ships as a gem with an executable at `exe/rubyn-code`. Talks to Claude via OAuth or API key.

- **Homepage:** https://rubyn.dev
- **License:** MIT
- **Ruby:** >= 3.3

## How a Prompt Flows

```
User input → CLI::REPL → Agent::Loop → LLM::Client (Claude)
                              ↕
                        Tools::Executor → Tool#execute
                              ↕
                     Context::Manager (compaction if needed)
                              ↕
                  Observability::BudgetEnforcer (cost check)
```

The `Agent::Loop` is the heartbeat. It sends messages to Claude, receives tool_use blocks,
dispatches them through `Tools::Executor` (which checks `Permissions::Policy` first),
appends results, and loops until Claude responds with plain text or the budget is exhausted.

## Project Layout

```
exe/rubyn-code           → Entry point: RubynCode::CLI::App.start(ARGV)
lib/rubyn_code.rb        → Root module, autoloads everything
lib/rubyn_code/          → 16 layers + infrastructure (see RUBYN.md in each dir)
db/migrations/           → Numbered .sql files (000_ through 010_)
skills/                  → 112 curated markdown skill documents
spec/                    → RSpec tests mirroring lib/ structure
```

## Architecture (16 layers + infrastructure)

Infrastructure: `CLI`, `LLM`, `Auth`, `DB`, `Config`, `Output`
Layers 1–16: `Agent` → `Tools` → `Permissions` → `Context` → `Skills` → `SubAgents` →
`Tasks` → `Background` → `Teams` → `Protocols` → `Autonomous` → `Memory` →
`Observability` → `Hooks` → `MCP` → `Learning`

Each has its own `RUBYN.md` in its directory. Start there.

## Error Hierarchy

```ruby
RubynCode::Error                 # Base — all custom errors descend from this
├── AuthenticationError          # OAuth/token failures
├── BudgetExceededError          # Cost limit hit
├── ConfigError                  # Bad/missing configuration
├── PermissionDeniedError        # Tool blocked by permission tier
├── StallDetectedError           # Agent loop detection triggered
└── ToolNotFoundError            # Unknown tool requested
```

## Database

SQLite at `~/.rubyn-code/rubyn_code.db`. Migrations are sequential `.sql` files in `db/migrations/`.

**Tables:** schema_migrations, sessions, messages, tasks, task_dependencies, memories,
cost_records, hooks, skills_cache, teams, instincts

## Conventions

- `# frozen_string_literal: true` in every file
- `autoload` over `require`
- RSpec for tests, RuboCop enforced (120 char lines, 25-line methods, 200-line classes)
- Single quotes unless interpolating
- Tools: inherit `Base`, define `schema`, implement `execute`
- Migrations: numbered sequentially (`000_`, `001_`), not timestamped
- No OpenStruct. Ever.

## Adding a New Tool

1. Create `lib/rubyn_code/tools/my_tool.rb` inheriting `Tools::Base`
2. Define `self.tool_name`, `self.description`, `self.schema` (JSON Schema for params)
3. Implement `execute(params)` — return a string result
4. Add autoload entry in `lib/rubyn_code.rb` under `module Tools`
5. Register in `Tools::Registry`

## Adding a New Skill

1. Create `skills/<category>/my-skill.md`
2. It auto-discovers via `Skills::Catalog` — no registration needed

## Git Workflow

This is a **public gem**. Never commit directly to `main`.

1. Create a feature branch: `git checkout -b <type>/<description>`
   - Types: `feat/`, `fix/`, `docs/`, `refactor/`, `test/`, `chore/`
2. Make focused commits with conventional messages
3. Push the branch and open a PR against `main`
4. PR must be reviewed before merge

**Repo config:** `user.name = "rubyn-code"`, `user.email = "admin@rubyn.ai"`
**Co-author line:** `Co-authored-by: Rubyn <admin@rubyn.ai>`

## Running

```bash
bundle install && ruby -Ilib exe/rubyn-code   # from source
bundle exec rspec                               # tests
bundle exec rubocop                             # lint
```
