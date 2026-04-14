# RUBYN.md — Rubyn Code

> Auto-loaded into agent context when working in this directory.

## What Is This?

`rubyn-code` (v0.1.0) — an AI-powered CLI coding assistant for Ruby and Rails.
Ships as a gem with an executable at `exe/rubyn-code`. Multi-provider: Anthropic (default),
OpenAI, and any OpenAI-compatible API (Groq, Together, Ollama, etc.).

- **Homepage:** https://rubyn.dev
- **License:** MIT
- **Ruby:** >= 3.3
- **Companion extension:** [`rubyn-code-vscode`](https://github.com/MatthewSuttles/rubyn-code-vscode)

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
lib/rubyn_code/ide/      → IDE integration layer (JSON-RPC server, handlers, adapters)
db/migrations/           → Numbered .sql and .rb files (000_ through 011_)
skills/                  → 112 curated markdown skill documents
protocol/                → Shared protocol schema and test fixtures (used by both repos)
spec/                    → RSpec tests mirroring lib/ structure
```

## Architecture (16 layers + infrastructure)

Infrastructure: `CLI`, `LLM`, `Auth`, `DB`, `Config`, `Output`
Layers 1–16: `Agent` → `Tools` → `Permissions` → `Context` → `Skills` → `SubAgents` →
`Tasks` → `Background` → `Teams` → `Protocols` → `Autonomous` → `Memory` →
`Observability` → `Hooks` → `MCP` → `Learning`

Each has its own `RUBYN.md` in its directory. Start there.

## IDE Integration (`lib/rubyn_code/ide/`)

The IDE layer provides a JSON-RPC 2.0 server that the VS Code extension (`rubyn-code-vscode`)
communicates with over stdio. Launched via `rubyn-code --ide`.

### IDE Architecture

```
VS Code Extension (client)
    ↕  stdin/stdout (newline-delimited JSON-RPC 2.0)
IDE::Server
    ├── Protocol          → parse/serialize/validate JSON-RPC messages
    ├── Client            → bidirectional RPC: CLI sends requests TO the extension
    ├── Handlers          → 14 registered request handlers
    └── Adapters
        └── ToolOutput    → gates tool execution, emits notifications, manages approvals
```

### IDE Components

| File | Purpose |
|------|---------|
| `ide/protocol.rb` | Pure JSON-RPC 2.0 message layer (parse, response, error, notification, serialize) |
| `ide/server.rb` | Main server: stdio read loop, dispatch, write mutex, signal traps |
| `ide/client.rb` | Sends JSON-RPC requests to the extension, blocks until response (ConditionVariable-based) |
| `ide/handlers.rb` | Handler registry with `REGISTRY` (method → class) and `SHORT_NAMES` (symbol → method) |
| `ide/adapters/tool_output.rb` | Wraps every tool call: emits notifications, gates mutations per permission mode |

### JSON-RPC Methods (Client → Server)

| Method | Handler | Purpose |
|--------|---------|---------|
| `initialize` | InitializeHandler | Handshake: workspace, version, capabilities |
| `prompt` | PromptHandler | Main chat — spawns agent loop in background thread |
| `cancel` | CancelHandler | Stop a running session |
| `review` | ReviewHandler | PR review with structured findings |
| `approveToolUse` | ApproveToolUseHandler | Approve/reject a mutating tool call |
| `acceptEdit` | AcceptEditHandler | Accept/reject a file edit preview |
| `shutdown` | ShutdownHandler | Graceful shutdown with session save |
| `config/get` | ConfigGetHandler | Read configuration values |
| `config/set` | ConfigSetHandler | Write configuration (validated against schema) |
| `models/list` | ModelsListHandler | Available models grouped by provider |
| `session/reset` | SessionResetHandler | Clear conversation for a session (like `/new`) |
| `session/list` | SessionListHandler | List past sessions with metadata |
| `session/resume` | SessionResumeHandler | Resume a session, restoring conversation history |
| `session/fork` | SessionForkHandler | Fork a session at a specific message index |

### JSON-RPC Methods (Server → Client — Bidirectional RPC)

The `IDE::Client` sends requests to the extension and blocks until a response arrives.
The server's `dispatch` detects response messages (id + result/error, no method) and
routes them to `Client#resolve`.

| Method | Purpose |
|--------|---------|
| `ide/openDiff` | Open a diff editor with proposed content |
| `ide/readSelection` | Read the user's current text selection |
| `ide/readActiveFile` | Read the active editor's content |
| `ide/saveFile` | Save a file |
| `ide/navigateTo` | Navigate to a file/line/column |
| `ide/getOpenTabs` | List all open editor tabs |
| `ide/getDiagnostics` | Get VS Code Problems panel diagnostics |
| `ide/getWorkspaceSymbols` | Search workspace symbols via language server |

### Notifications (Server → Client)

| Method | Purpose |
|--------|---------|
| `stream/text` | Streamed text chunks (partial + final) |
| `agent/status` | Agent state changes (thinking, streaming, done, error, cancelled) |
| `tool/use` | Tool invocation with args and requiresApproval flag |
| `tool/result` | Tool execution result with summary |
| `file/edit` | File modification preview for diff editor |
| `file/create` | New file preview |
| `review/finding` | Structured review finding (severity, file, line, message) |
| `session/cost` | Token usage and cost snapshot |
| `config/changed` | Config value changed notification |

### Permission Modes

The `ToolOutput` adapter gates tool execution based on a permission mode (set via
`--permission-mode` CLI flag or `config/set` at runtime). Replaces the old binary
`--yolo` flag.

| Mode | Behavior |
|------|----------|
| `default` | Prompt for every mutating tool and file edit |
| `accept_edits` | Auto-approve file edits, prompt for bash and other mutations |
| `plan_only` | Read-only — block all write operations (raises `UserDeniedError`) |
| `auto` | Auto-approve everything except deny-listed |
| `dont_ask` | Auto-deny all non-read-only tools |
| `bypass` | No checks — auto-approve everything (legacy `--yolo`) |

`--yolo` is still accepted as an alias for `--permission-mode bypass`.

### IDE-Only Tools

Two tools are conditionally registered when `ide_client` is available (IDE mode only):

| Tool | Calls | Purpose |
|------|-------|---------|
| `ide_diagnostics` | `ide/getDiagnostics` | VS Code Problems panel errors/warnings |
| `ide_symbols` | `ide/getWorkspaceSymbols` | Language server symbol search |

These are in `tools/ide_diagnostics.rb` and `tools/ide_symbols.rb`. They accept an
`ide_client:` keyword in their constructor. The `Tools::Executor` passes `ide_client`
automatically when building IDE-aware tools. Registration happens via
`Tools::Registry.load_ide_tools!` (called by PromptHandler).

### Tool Execution Flow (IDE Mode)

1. Agent calls tool via `Tools::Executor`
2. `ToolOutput` adapter intercepts via `wrap_execution(name, args, &block)`
3. Adapter classifies tool: read-only vs file-write vs mutating
4. Gating depends on permission mode (see table above)
5. For gated tools: emits `tool/use` notification, blocks on `ConditionVariable` (60s timeout)
6. Extension responds with `approveToolUse` or `acceptEdit`
7. `ApproveToolUseHandler` / `AcceptEditHandler` calls `resolve_approval` / `resolve_edit`
8. On denial: raises `UserDeniedError` (signals to model: refusal not success)

### Adding a New IDE Handler

1. Create `lib/rubyn_code/ide/handlers/my_handler.rb`
2. Constructor takes `(server)`, implement `call(params)` returning a result hash
3. Add `require_relative` in `handlers.rb`
4. Add entry to `REGISTRY` hash (method string → class)
5. Add entry to `SHORT_NAMES` hash (symbol → method string)
6. Add params/result schemas to `protocol/schema.json`
7. Add a fixture to `protocol/fixtures/`
8. Add spec in `spec/rubyn_code/ide/handlers/`

### Protocol Schema and Contract Tests

`protocol/schema.json` is the single source of truth for every JSON-RPC message shape.
Both repos validate against it:

- **Ruby:** `spec/rubyn_code/ide/contract_spec.rb` uses `json_schemer` to validate
  fixtures against the schema
- **VS Code:** `test/contract/protocol-contract.test.ts` uses `ajv` to do the same
- **Fixtures:** `protocol/fixtures/*.json` contain full request/response/notification
  sequences for each lifecycle scenario

When adding or modifying a JSON-RPC method, update `schema.json` first, then update
fixtures, then run both test suites.

### Session Management

Sessions persist conversation history across prompts within the same session ID.

- **Multi-turn:** `PromptHandler` caches `Agent::Conversation` objects per session ID.
  Each prompt reuses the existing conversation (new `Agent::Loop`, same messages array).
- **Reset:** `session/reset` drops the cached conversation; next prompt starts fresh.
- **Resume:** `session/resume` loads a saved session from `SessionPersistence`, creates a
  new `Conversation` with the stored messages, and injects it via
  `PromptHandler#inject_conversation`.
- **Fork:** `session/fork` loads a session, truncates at a message index, saves as new session.
- **List:** `session/list` returns past sessions with metadata (title, timestamp, message count).

### Config Validation

`Config::Validator` (in `lib/rubyn_code/config/validator.rb`) validates config values
against `lib/rubyn_code/config/schema.json` using `json_schemer`. The `config/set`
handler rejects invalid values before persisting.

Validated keys: `provider`, `model`, `model_mode` (auto/manual), `max_iterations` (1–1000),
`max_sub_agent_iterations` (1–500), `max_output_chars` (1000–1000000),
`context_threshold_tokens` (10000–200000), `session_budget_usd` (0.1–100),
`daily_budget_usd` (0.5–500).

## Hooks System (`lib/rubyn_code/hooks/`)

Thread-safe hook registry with priority-ordered execution. Hooks are callables
registered per event type.

### Hook Events

| Event | Semantics | Fired By |
|-------|-----------|----------|
| `pre_tool_use` | If any hook returns `{ deny: true }`, tool is blocked | Agent loop |
| `post_tool_use` | Pipeline: each hook receives previous output | Agent loop |
| `pre_llm_call` | Run before each LLM request | Agent loop |
| `post_llm_call` | Run after each LLM response | Agent loop |
| `on_stall` | Agent loop stall detected | Agent loop |
| `on_error` | Error during agent execution | Agent loop |
| `on_session_end` | Session ending | Agent loop |
| `session_start` | First prompt in a session (IDE mode) | PromptHandler |
| `user_prompt_submit` | Every prompt submission (IDE mode) | PromptHandler |
| `permission_request` | Before waiting for tool/edit approval (IDE mode) | ToolOutput adapter |
| `stop` | Session cancelled (IDE mode) | CancelHandler |

### Built-in Hooks

- `CostTrackingHook` — records LLM usage via `BudgetEnforcer` (`post_llm_call`)
- `LoggingHook` — logs tool calls and results (`pre_tool_use`, `post_tool_use`)
- `AutoCompactHook` — triggers context compaction (`post_llm_call`)

## Error Hierarchy

```ruby
RubynCode::Error                 # Base — all custom errors descend from this
├── AuthenticationError          # OAuth/token failures
├── BudgetExceededError          # Cost limit hit
├── ConfigError                  # Bad/missing configuration
├── PermissionDeniedError        # Tool blocked by permission tier
├── StallDetectedError           # Agent loop detection triggered
├── ToolNotFoundError            # Unknown tool requested
└── UserDeniedError              # User refused tool/edit in IDE mode
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
- IDE handlers: constructor takes `(server)`, implement `call(params)` returning a result hash

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

For IDE-only tools (tools that call `ide/*` RPC methods):
1. Accept `ide_client:` as a keyword arg in the constructor
2. Add the tool name to `Registry::IDE_ONLY_TOOLS` (excluded from `load_all!`, loaded by `load_ide_tools!`)
3. The `Executor` detects the `ide_client:` constructor parameter and passes it automatically

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

Pass `--key` when adding a provider, or set it separately:

```
/provider add groq https://api.groq.com/openai/v1 --key gsk-your-key --models llama-3.3-70b
/provider set-key groq gsk-new-key
```

Keys are stored in `~/.rubyn-code/tokens.yml` (permissions `0600`).

**Resolution order:** stored key in tokens.yml → environment variable → error.

Environment variables work as a fallback. Rubyn checks `env_key` from config, or derives
`<PROVIDER_NAME>_API_KEY` (uppercased, hyphens become underscores). For example, provider
`bedrock-proxy` checks `BEDROCK_PROXY_API_KEY`.

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

## CLI Flags

```
rubyn-code                           Start interactive REPL
rubyn-code -p "prompt"               Run a single prompt and exit
rubyn-code --resume [ID]             Resume a previous session
rubyn-code --ide                     Start IDE server (VS Code extension)
rubyn-code --permission-mode MODE    Set permission mode (see Permission Modes section)
rubyn-code --yolo                    Alias for --permission-mode bypass
rubyn-code --debug                   Enable debug output
rubyn-code --auth                    OAuth authentication
rubyn-code --setup                   Pin rubyn-code to bypass rbenv/rvm
rubyn-code daemon [options]          Start autonomous daemon (GOLEM)
```

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

### Running IDE contract tests (both repos must be checked out as siblings)

```bash
# Ruby side
bundle exec rspec spec/rubyn_code/ide/contract_spec.rb

# VS Code side (from rubyn-code-vscode/)
npx vitest run test/contract/
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
