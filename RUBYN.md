# RUBYN.md — Rubyn Code

> Auto-loaded into agent context when working in this directory.

## What Is This?

`rubyn-code` (v0.1.0) — an AI-powered CLI coding assistant for Ruby and Rails.
Ships as a gem with an executable at `exe/rubyn-code`. Multi-provider: Anthropic (default),
OpenAI, and any OpenAI-compatible API (Groq, Together, Ollama, etc.).

- **Homepage:** https://rubyn.dev
- **License:** MIT
- **Ruby:** >= 3.3

## How a Prompt Flows

```
User input → CLI::REPL
                ├── /command → Commands::Registry → Command#execute
                │                                      ↓
                │                              (optional action hash → REPL state change)
                │
                └── message → Agent::Loop → LLM::Client (facade)
                                   ↕                    ↓
                             Tools::Executor    Adapters::Anthropic / OpenAI / OpenAICompatible
                                   ↕
                                   ↕
                          Context::Manager (compaction if needed)
                                   ↕
                       Observability::BudgetEnforcer (cost check)
```

The `Agent::Loop` is the heartbeat. It sends messages to the LLM (via the adapter layer),
receives tool_use blocks, dispatches them through `Tools::Executor` (which checks
`Permissions::Policy` first), appends results, and loops until the LLM responds with
plain text or the budget is exhausted. The loop also guards against empty responses
(retries automatically) and waits for background jobs before finalizing.

Slash commands (`/help`, `/plan`, `/doctor`, etc.) are handled locally by the
`Commands::Registry` — they never hit the LLM. See `cli/commands/RUBYN.md`.

## Project Layout

```
exe/rubyn-code           → Entry point: RubynCode::CLI::App.start(ARGV)
lib/rubyn_code.rb        → Root module, autoloads everything
lib/rubyn_code/          → 16 layers + infrastructure (see RUBYN.md in each dir)
db/migrations/           → Numbered .sql and .rb files (000_ through 011_)
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

SQLite at `~/.rubyn-code/rubyn_code.db`. Migrations are sequential files in `db/migrations/`.

**Migration formats:**
- `.sql` — executed statement-by-statement inside a transaction
- `.rb` — Ruby module with `module_function def up(db)` for conditional/complex migrations

**Tables:** schema_migrations, sessions, messages, tasks, task_dependencies, memories,
cost_records, hooks, skills_cache, teammates, mailbox_messages, instincts

## Conventions

- `# frozen_string_literal: true` in every file
- `autoload` over `require`
- RSpec for tests, RuboCop enforced (120 char lines, 25-line methods, 200-line classes)
- Single quotes unless interpolating
- Tools: inherit `Base`, define `schema`, implement `execute`
- Migrations: numbered sequentially (`000_`, `001_`), not timestamped. Use `.sql` for simple DDL, `.rb` when you need conditional logic
- No OpenStruct. Ever.

## Slash Commands

20 commands, each in its own file under `lib/rubyn_code/cli/commands/`. Registry-based
dispatch with tab-completion. Infrastructure: `Base` (abstract), `Registry` (dispatch),
`Context` (Data.define with all deps).

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/doctor` | Environment health check (Ruby, gems, DB, API, skills) |
| `/tokens` | Token estimation for current context |
| `/plan` | Toggle plan mode (reason without executing) |
| `/context` | Visual context window usage bar |
| `/diff` | Quick git diff |
| `/model` | Show/switch model (supports provider:model syntax) |
| `/provider` | Add or list providers |
| `/review` | PR review against best practices |
| `/skill` | Load/list skills |
| `/tasks` | List active tasks |
| `/spawn` | Spawn a teammate agent |
| `/resume` | Restore a previous session |
| `/compact` | Manual context compaction |
| `/budget` | Show/set spending limit |
| `/cost` | Session cost summary |
| `/clear` | Clear terminal |
| `/undo` | Remove last exchange |
| `/version` | Show version |
| `/quit` | Exit (aliases: `/exit`, `/q`) |

Commands return optional **action hashes** for state changes the REPL processes
(e.g., `{ action: :set_plan_mode, enabled: true }`).

## Adding a New Command

1. Create `lib/rubyn_code/cli/commands/my_command.rb` inheriting `Commands::Base`
2. Define `self.command_name` (with `/` prefix), `self.description`, `execute(args, ctx)`
3. Add autoload entry in `lib/rubyn_code.rb` under `module Commands`
4. Register in `REPL#setup_command_registry!`
5. Add spec in `spec/rubyn_code/cli/commands/my_command_spec.rb`

## Adding a New Tool

1. Create `lib/rubyn_code/tools/my_tool.rb` inheriting `Tools::Base`
2. Define `self.tool_name`, `self.description`, `self.schema` (JSON Schema for params)
3. Implement `execute(params)` — return a string result
4. Add autoload entry in `lib/rubyn_code.rb` under `module Tools`
5. Register in `Tools::Registry`

## Adding a New LLM Adapter

1. Create `lib/rubyn_code/llm/adapters/my_provider.rb` inheriting `Adapters::Base`
2. Implement `#chat(messages:, model:, max_tokens:, tools:, system:, on_text:, task_budget:)`,
   `#provider_name`, and `#models`
3. `#chat` must return `LLM::Response` with normalized `TextBlock` / `ToolUseBlock` / `Usage`
4. Stop reasons must be normalized: `'end_turn'`, `'tool_use'`, `'max_tokens'`
5. Add autoload entry in `lib/rubyn_code.rb` under `module Adapters`
6. Add spec in `spec/rubyn_code/llm/adapters/` — include `it_behaves_like 'an LLM adapter'`

## Adding a Custom Provider

Use the `/provider` command or edit `~/.rubyn-code/config.yml` directly.

### Via slash command

```
/provider add groq https://api.groq.com/openai/v1 --env-key GROQ_API_KEY --models llama-3.3-70b,mixtral-8x7b
```

For providers that use the Anthropic Messages API format instead of OpenAI:

```
/provider add bedrock-proxy https://proxy.example.com/v1 --format anthropic --env-key PROXY_API_KEY --models claude-sonnet-4-6
```

### Via config.yml

```yaml
providers:
  groq:
    base_url: https://api.groq.com/openai/v1
    env_key: GROQ_API_KEY
    models:
      cheap: llama-3.3-70b
      top: llama-3.3-70b
  bedrock-proxy:
    api_format: anthropic          # 'openai' (default) or 'anthropic'
    base_url: https://proxy.example.com/v1
    env_key: PROXY_API_KEY
    models:
      top: claude-sonnet-4-6
```

### Setting up the API key

Rubyn Code resolves API keys from the environment variable named in `env_key`. Set it in
your shell profile (`~/.zshrc`, `~/.bashrc`, etc.):

```bash
export GROQ_API_KEY="gsk-your-key-here"
export OPENAI_API_KEY="sk-your-key-here"
```

If `env_key` is not specified in the config, Rubyn derives it from the provider name:
`<PROVIDER_NAME>_API_KEY` (uppercased, hyphens become underscores). For example, provider
`bedrock-proxy` looks for `BEDROCK_PROXY_API_KEY`.

Local providers (localhost / 127.0.0.1) skip the API key requirement entirely.

### Switching providers

```
/model groq:llama-3.3-70b          # switch provider and model
/model groq:                        # switch provider, keep current model
/model                              # show current + all configured providers
/provider list                      # list all providers with their models
```

**Key files in the adapter layer:**
- `adapters/base.rb` — abstract contract (chat, provider_name, models)
- `adapters/anthropic.rb` — Anthropic Claude (OAuth + API key, prompt caching, SSE streaming)
- `adapters/openai.rb` — OpenAI Chat Completions (Bearer auth, function calling, SSE streaming)
- `adapters/anthropic_compatible.rb` — inherits Anthropic, overrides base_url/provider/models/auth (for Anthropic-format proxies)
- `adapters/openai_compatible.rb` — inherits OpenAI, overrides base_url/provider/models/auth
- `adapters/openai_message_translator.rb` — translates Anthropic-format messages to OpenAI format
- `adapters/openai_streaming.rb` — SSE parser for OpenAI `choices[0].delta` format
- `adapters/anthropic_streaming.rb` — SSE parser for Anthropic `content_block_delta` format
- `adapters/json_parsing.rb` — shared safe JSON parsing
- `adapters/prompt_caching.rb` — Anthropic-only cache_control injection
- `shared_examples.rb` (in spec) — adapter contract shared examples

**Important patterns:**
- All adapters return the same `LLM::Response` / `TextBlock` / `ToolUseBlock` / `Usage` types
- `TextBlock`, `ToolUseBlock`, `Response`, `Usage` are `Data.define` objects in `message_builder.rb`
- Any file referencing these types needs `require_relative '../message_builder'`
- `STOP_REASON_MAP` lives in `OpenAIStreaming` — the OpenAI adapter references it from there
- `OpenAICompatible` passes `base_url` to `OpenAI`; `api_url` appends `/chat/completions`
- Local providers (localhost/127.0.0.1) skip API key requirement via `local_provider?`
- Tool schemas: Anthropic uses `input_schema`, OpenAI wraps in `{ type: "function", function: { parameters: ... } }`
- Message format: Anthropic tool_results are `role: "user"` with `type: "tool_result"` blocks;
  OpenAI uses `role: "tool"` with `tool_call_id`. The translator handles this.

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

## Agent Loop Changes

Any modification to the agent loop (`lib/rubyn_code/agent/loop.rb`, `llm_caller.rb`,
`tool_processor.rb`, or `context/manager.rb`) **must** be followed by running the
self-test skill (`/skill self-test`) to verify Rubyn isn't broken. The self-test runs
25+ automated checks across all major subsystems — file ops, search, bash, git, specs,
the efficiency engine, skills, memory, config, codebase index, slash commands, and
architecture integrity. If the self-test fails, fix the regression before committing.

## Pre-Commit Checklist

**Always run both before committing:**

```bash
bundle exec rspec && bundle exec rubocop
```

Do NOT commit if either fails. Fix lint offenses before pushing — RuboCop is enforced
(120 char lines, 25-line methods, 200-line classes).
