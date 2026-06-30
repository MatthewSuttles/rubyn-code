# Architecture Guide

## What Is Rubyn Code?

Rubyn Code is an AI-powered CLI coding assistant for Ruby and Rails. It ships as a
gem (`rubyn-code`) with an executable at `exe/rubyn-code` and supports multiple LLM
providers: Anthropic (default), OpenAI, and any OpenAI-compatible API (Groq,
Together, Ollama, etc.).

The system is built around a **16-layer agentic architecture** plus
**infrastructure modules** that handle the CLI, LLM communication, authentication,
database persistence, configuration, and output formatting. Each layer has a
focused responsibility and interacts with other layers through well-defined
interfaces.

## The 16 Layers

### Layer 1: Agent

**Purpose:** The core agentic loop -- the heartbeat of the entire system.

**Key classes:**
- `Agent::Loop` -- Sends conversation to the LLM, receives responses. When the
  response contains `tool_use` blocks, dispatches them via `Tools::Executor`,
  appends results, and loops. Stops when the LLM returns plain text, the budget is
  exhausted, or `MAX_ITERATIONS` is reached.
- `Agent::Conversation` -- In-memory conversation state. Holds the messages array
  (user turns, assistant turns, tool results). Supports undo, clear, and context
  compaction.
- `Agent::LoopDetector` -- Detects when the agent is stuck calling the same tool
  with the same arguments. Uses a sliding window (default: 5) with a threshold
  (default: 3 identical calls). Raises `StallDetectedError` when triggered.
- `Agent::ResponseModes` -- Handles different response modes (normal, plan mode).
- `Agent::DynamicToolSchema` -- Filters tool schemas sent to the LLM based on
  detected task context, reducing per-turn system prompt overhead by 30-50%.

**Interactions:** Collaborates with `Tools::Executor` (Layer 2), `Context::Manager`
(Layer 4), `Hooks::Runner` (Layer 14), and `Observability::BudgetEnforcer` (Layer
13). The loop also integrates with `Skills::TtlManager` (Layer 5) and
`Context::DecisionCompactor` (Layer 4) for intelligent context management.

---

### Layer 2: Tools

**Purpose:** 32 built-in tools that the LLM can invoke. The extensibility surface
of the system.

**Key classes:**
- `Tools::Base` -- Abstract base class. Subclasses define `TOOL_NAME`,
  `DESCRIPTION`, `PARAMETERS` (JSON Schema), `RISK_LEVEL`, and implement
  `execute(**params)`. Returns a string result.
- `Tools::Registry` -- Maps tool names to classes. Tools self-register via
  `Registry.register(ToolClass)`. `Registry.find('read_file')` returns the tool
  class.
- `Tools::Schema` -- Converts tool classes into the LLM's expected tool definition
  format (name, description, input_schema).
- `Tools::Executor` -- Dispatches tool calls. Checks `Permissions::Policy` before
  execution, wraps errors, and returns results.

**Tool categories:**

| Category | Tools |
|----------|-------|
| File I/O | `read_file`, `write_file`, `edit_file`, `glob`, `grep` |
| Shell | `bash`, `background_run` |
| Rails | `rails_generate`, `db_migrate`, `run_specs`, `bundle_install`, `bundle_add` |
| Git | `git_commit`, `git_diff`, `git_log`, `git_status` |
| Web | `web_search`, `web_fetch` |
| Memory | `memory_search`, `memory_write` |
| Agents | `spawn_agent`, `spawn_teammate`, `send_message`, `read_inbox` |
| Meta | `compact`, `load_skill`, `task`, `review_pr`, `ask_user` |

**Interactions:** Called by `Agent::Loop` (Layer 1), gated by `Permissions::Policy`
(Layer 3), and observable via `Hooks::Runner` (Layer 14).

---

### Layer 3: Permissions

**Purpose:** Tiered permission system controlling which tools the agent can use.

**Key classes:**
- `Permissions::Tier` -- Defines permission tiers (e.g. `:readonly`, `:edit`,
  `:admin`). Each tier grants access to a set of tools. Higher tiers include all
  lower-tier tools.
- `Permissions::Policy` -- Evaluates whether a tool call is allowed given the
  current tier. Consulted by `Tools::Executor` before every tool invocation.
- `Permissions::DenyList` -- Explicit tool deny list. Overrides tier permissions.
  Configurable per-project via `.rubyn-code.yml`.
- `Permissions::Prompter` -- Asks the user for permission when a tool requires
  escalation. Renders the tool name and arguments, waits for yes/no confirmation.

**Interactions:** `Tools::Executor` (Layer 2) checks `Policy` before every tool
call. `DenyList` is configurable via `Config` (infrastructure).

---

### Layer 4: Context Management

**Purpose:** Manages the conversation context window to stay within the LLM's token
limits through a multi-layered compression strategy.

**Key classes:**
- `Context::Manager` -- Orchestrates context strategy. Tracks token usage, decides
  when compaction is needed, selects the right compaction strategy.
- `Context::MicroCompact` -- Zero-cost compression that replaces old tool results
  with short placeholders (e.g. `[Previous: used read_file]`). Runs when context
  reaches 70% of threshold.
- `Context::ContextCollapse` -- Lightweight reduction that removes old conversation
  turns without calling the LLM. Keeps the first message and recent N exchanges,
  snips everything in between.
- `Context::Compactor` / `Context::AutoCompact` -- LLM-driven summarization as a
  last resort. Sends the conversation to a cheaper model for summarization and
  replaces old messages with the summary.
- `Context::ManualCompact` -- Triggered by the user via `/compact`. Accepts a focus
  area for the summary.
- `Context::DecisionCompactor` -- Triggers compaction at logical decision boundaries
  (specs passed, topic switch, multi-file edit complete) rather than only at
  capacity limits.
- `Context::ContextBudget` -- Budget-aware context loader that prioritizes related
  files (full content vs. signatures-only) within a token budget.
- `Context::SchemaFilter` -- Extracts only relevant table definitions from
  `db/schema.rb` based on which models are in context.

**Interactions:** Called by `Agent::Loop` (Layer 1) before and after LLM calls.
`AutoCompactHook` in `Hooks::BuiltIn` (Layer 14) also triggers compaction checks.

---

### Layer 5: Skills

**Purpose:** 112 curated markdown skill documents loaded on demand into the LLM
context.

**Key classes:**
- `Skills::Catalog` -- Discovers all skill files under configured directories and
  builds a searchable index. Maps slash-names to file paths. No registration
  needed -- drop a `.md` file in the right category directory.
- `Skills::Loader` -- Loads a skill document by name, formats it as XML for the
  LLM context, and caches loaded skills.
- `Skills::Document` -- Parses skill markdown files. Supports YAML frontmatter
  (name, description, tags) or derives metadata from content/filename.
- `Skills::TtlManager` -- Tracks skill TTL (time-to-live) with a turn counter.
  Skills that are not referenced within their TTL (default: 5 turns) are ejected
  during the next compaction pass.

**Interactions:** `Agent::Loop` (Layer 1) injects skill listings into the system
prompt. `Tools::LoadSkill` (Layer 2) loads individual skills on demand.

---

### Layer 6: Sub-Agents

**Purpose:** Isolated agents spawned for specific tasks with scoped access.

**Key classes:**
- `SubAgents::Runner` -- Spawns a sub-agent with its own fresh conversation
  context. Two types: `explore` (read-only tools) and `worker` (full write access).
  The sub-agent runs its own `Agent::Loop`, completes its task, and returns only a
  summary.
- `SubAgents::Summarizer` -- Compresses a sub-agent's full conversation into a
  concise summary for the parent agent. Keeps the parent's context clean.

**Interactions:** Triggered by `Tools::SpawnAgent` (Layer 2). Uses `Agent::Loop`
(Layer 1) internally.

---

### Layer 7: Tasks

**Purpose:** Task tracking with DAG-based dependency management.

**Key classes:**
- `Tasks::Manager` -- CRUD operations for tasks. Persists to the `tasks` SQLite
  table. Supports status tracking, priority, ownership, and dependency resolution.
- `Tasks::DAG` -- Directed acyclic graph for task dependencies. Determines which
  tasks are ready to run (all dependencies met), detects cycles, and computes
  execution order.
- `Tasks::Models` -- Data objects for tasks and dependencies. Maps to/from SQLite
  rows.

**Interactions:** Surfaced by `Tools::Task` (Layer 2) and `/tasks` command (CLI).
Used by `Autonomous::TaskClaimer` (Layer 11) for daemon execution.

---

### Layer 8: Background

**Purpose:** Background job execution for long-running commands.

**Key classes:**
- `Background::Worker` -- Manages background processes. Spawns commands in
  subprocesses, tracks their PIDs, and collects output when complete.
- `Background::Job` -- Represents a single background job: command, PID, status,
  output.
- `Background::Notifier` -- Delivers background job results back to the agent.
  Injects completed job output into the conversation before the next LLM call.

**Interactions:** Triggered by `Tools::BackgroundRun` (Layer 2). `Agent::Loop`
(Layer 1) drains background notifications before each iteration.

---

### Layer 9: Teams

**Purpose:** Persistent named teammate agents with asynchronous mailbox messaging.

**Key classes:**
- `Teams::Manager` -- Spawns and manages persistent teammate agents. Each teammate
  has a name, role, and its own conversation context. Persisted in SQLite.
- `Teams::Teammate` -- Represents a single teammate: name, role, conversation
  state, status. Processes messages from its mailbox and can send messages back.
- `Teams::Mailbox` -- Asynchronous message queue between agents. `send_message`
  enqueues, `read_inbox` dequeues. Messages are typed (`:message`, `:task`,
  `:result`).

**Interactions:** Triggered by `Tools::SpawnTeammate` (Layer 2) and
`Tools::SendMessage` / `Tools::ReadInbox` (Layer 2). `/spawn` command (CLI) also
creates teammates.

---

### Layer 10: Protocols

**Purpose:** Safety and coordination protocols for agent lifecycle.

**Key classes:**
- `Protocols::ShutdownHandshake` -- Graceful shutdown. Waits for the current tool
  call to complete, saves conversation state, and cleans up resources.
- `Protocols::PlanApproval` -- When the agent proposes a multi-step plan, prompts
  the user for approval before execution. Shows the plan, waits for
  yes/no/edit.
- `Protocols::InterruptHandler` -- Traps SIGINT (Ctrl+C). First interrupt cancels
  the current operation. Second interrupt within 2 seconds triggers shutdown.

**Interactions:** `InterruptHandler` is wired into `CLI::REPL`. `PlanApproval`
integrates with `Agent::ResponseModes` (Layer 1). `ShutdownHandshake` coordinates
with `Background::Worker` (Layer 8) and `Memory::SessionPersistence` (Layer 12).

---

### Layer 11: Autonomous

**Purpose:** Daemon mode for hands-off task execution.

**Key classes:**
- `Autonomous::Daemon` -- Runs the agent in background mode. Polls for unclaimed
  tasks, executes them, and reports results. No human in the loop.
- `Autonomous::IdlePoller` -- Watches for new tasks at a configurable interval.
  Wakes the daemon when work is available.
- `Autonomous::TaskClaimer` -- Atomically claims tasks from the DAG to prevent
  double-execution when multiple agents are running.

**Interactions:** Uses `Tasks::DAG` (Layer 7) for work discovery and `Agent::Loop`
(Layer 1) for execution. Managed via `CLI::DaemonRunner`.

---

### Layer 12: Memory

**Purpose:** Persistent cross-session memory backed by SQLite.

**Key classes:**
- `Memory::Store` -- Writes memories to the `memories` table. Each memory has
  content, category (`code_pattern`, `user_preference`, `project_convention`,
  `error_resolution`, `decision`), and a retention tier (`short`, `medium`,
  `long`).
- `Memory::Search` -- Full-text search across memories. Filters by category and
  tier. Used by the agent to recall context from previous sessions.
- `Memory::SessionPersistence` -- Saves and restores session state (conversation,
  tasks, costs) across REPL sessions. Keyed by session ID in the `sessions` table.
- `Memory::Models` -- Data objects mapping to/from SQLite memory rows.

**Interactions:** Surfaced by `Tools::MemorySearch` and `Tools::MemoryWrite`
(Layer 2). `SessionPersistence` integrates with `CLI::REPL` and `/resume` command.
`Learning::Extractor` (Layer 16) creates memories automatically.

---

### Layer 13: Observability

**Purpose:** Token counting, cost tracking, and budget enforcement.

**Key classes:**
- `Observability::TokenCounter` -- Estimates token counts for messages and tool
  results. Used by `Context::Manager` (Layer 4) for compaction decisions.
- `Observability::CostCalculator` -- Computes cost per API call based on model,
  input/output tokens. Persists records to the `cost_records` table.
- `Observability::BudgetEnforcer` -- Enforces per-session and global budget caps.
  Raises `BudgetExceededError` when the limit is hit. Checked in `Agent::Loop`
  before each API call.
- `Observability::UsageReporter` -- Generates usage summaries: tokens used, cost
  breakdown, session stats. Powers the `/cost` and `/budget` slash commands.
- `Observability::TokenAnalytics` -- Detailed token usage analytics and trends.
- `Observability::SkillAnalytics` -- Tracks which skills are loaded and their token
  cost.

**Interactions:** `BudgetEnforcer` is checked by `Agent::Loop` (Layer 1).
`CostTrackingHook` in `Hooks::BuiltIn` (Layer 14) records costs after each LLM
call.

---

### Layer 14: Hooks

**Purpose:** Event hooks for extending agent behavior without modifying core code.

**Key classes:**
- `Hooks::Registry` -- Thread-safe storage for hook callables keyed by event type.
  Supports priorities (lower runs first).
- `Hooks::Runner` -- Executes registered hooks when events fire. Defensive
  execution: exceptions are caught and logged. Special semantics for `pre_tool_use`
  (deny gating) and `post_tool_use` (output transformation pipeline).
- `Hooks::BuiltIn` -- Default hooks: cost tracking, tool-call logging, auto-compact
  triggers.
- `Hooks::UserHooks` -- Loads user-defined hooks from YAML configuration files.
  Supports `deny` and `log` actions with tool/path/match pattern filtering.

**Interactions:** `Agent::Loop` (Layer 1) fires hooks via `Runner`. All layers can
register hooks on the `Registry`.

See [HOOKS.md](HOOKS.md) for the complete hooks reference.

---

### Layer 15: MCP (Model Context Protocol)

**Purpose:** Client for connecting to external MCP tool servers, extending the
tool set dynamically.

**Key classes:**
- `MCP::Client` -- JSON-RPC 2.0 client that discovers and invokes tools on MCP
  servers. Handles initialization, tool listing, and tool execution.
- `MCP::StdioTransport` -- Subprocess transport via `Open3.popen3`. Communicates
  over stdin/stdout with newline-delimited JSON-RPC.
- `MCP::SSETransport` -- HTTP Server-Sent Events transport. Long-lived GET for
  events, POST for JSON-RPC requests.
- `MCP::ToolBridge` -- Dynamically creates `Tools::Base` subclasses from MCP tool
  definitions. Prefixes tool names with `mcp_`, sets risk level to `:external`, and
  registers them in `Tools::Registry`.
- `MCP::Config` -- Loads MCP server configuration from `.rubyn-code/mcp.json`.
  Supports environment variable interpolation via `${VAR}` syntax.

**Interactions:** `ToolBridge` registers dynamically created tools in
`Tools::Registry` (Layer 2). `Tools::Executor` (Layer 2) can then invoke them like
any built-in tool.

---

### Layer 16: Learning

**Purpose:** Continuous learning from session patterns with confidence decay.

**Key classes:**
- `Learning::Extractor` -- Post-session analysis using a cheaper LLM (Haiku). Scans
  the last 30 messages for patterns: error resolutions, user corrections,
  workarounds, debugging techniques, project-specific conventions. Persists as
  instincts.
- `Learning::Instinct` -- A learned pattern with a confidence score that decays
  over time. Stored in the `instincts` SQLite table. Higher confidence = more
  likely to be injected into future prompts.
- `Learning::Injector` -- Selects relevant instincts (confidence >= 0.3, max 10)
  and injects them into the system prompt for the current session. Filters by
  project context.
- `Learning::Shortcut` -- Learned shortcuts for common operations.

**Interactions:** `Extractor` runs at session end (triggered by `on_session_end`
hook in Layer 14). `Injector` runs at session start in `Agent::Loop` (Layer 1).

---

## Message Lifecycle

The journey of a user message from input to response:

```
1. User types a message in the terminal
                |
2. CLI::InputHandler classifies it:
   ├── Slash command (/help, /plan, etc.)
   │   └── Commands::Registry dispatches to the matching Command#execute
   │       └── Returns optional action hash to REPL (e.g. toggle plan mode)
   │
   └── Regular message
       |
3. Agent::Loop#send_message is called
   ├── initialize_session! (project profile, codebase index -- first turn only)
   ├── check_user_feedback (detect corrections to prior answers)
   ├── drain_background_notifications (inject completed job results)
   ├── inject_skill_listing (available skills -- first turn only)
   ├── detect_topic_switch (decision compactor)
   ├── skill_ttl.tick! (advance skill turn counter)
   └── conversation.add_user_message(input)
       |
4. Iteration loop (up to MAX_ITERATIONS):
   ├── compact_if_needed (check context size, run compaction strategies)
   ├── call_llm (build system prompt, select tool schemas, call adapter)
   │   ├── DynamicToolSchema filters tools by detected task context
   │   ├── LLM::Client delegates to active adapter (Anthropic/OpenAI/Compatible)
   │   └── Hooks fire: pre_llm_call, post_llm_call
   │
   ├── If response has tool_use blocks:
   │   ├── Hooks fire: pre_tool_use (may deny)
   │   ├── Permissions::Policy checks access tier
   │   ├── Tools::Executor dispatches to the tool
   │   ├── Hooks fire: post_tool_use (may transform output)
   │   ├── Tool result appended to conversation
   │   └── Loop continues (go to step 4)
   │
   └── If response is plain text:
       ├── Handle truncation recovery if needed
       ├── Wait for pending background jobs
       ├── DecisionCompactor checks for logical compaction points
       ├── compact_if_needed (post-response)
       └── Return text to REPL for rendering
                |
5. CLI::Renderer displays the response
   └── CLI::StreamFormatter handles real-time streaming with syntax highlighting
```

---

## Data Flow Diagram

```
                                 +-----------------+
                                 |   User (TTY)    |
                                 +--------+--------+
                                          |
                                   user input / display
                                          |
                                 +--------v--------+
                                 |   CLI::REPL     |
                                 |  InputHandler   |
                                 |  Renderer       |
                                 +--------+--------+
                                          |
                          +---------------+---------------+
                          |                               |
                  /slash command                    message text
                          |                               |
                 +--------v--------+             +--------v--------+
                 | Commands::      |             |  Agent::Loop    |
                 | Registry        |             |  (heartbeat)    |
                 +-----------------+             +--------+--------+
                                                          |
                                          +---------------+---------------+
                                          |                               |
                                  +-------v-------+              +--------v--------+
                                  | LLM::Client   |              | Tools::Executor |
                                  | (facade)      |              | (dispatch)      |
                                  +-------+-------+              +--------+--------+
                                          |                               |
                              +-----------+-----------+          +--------v--------+
                              |           |           |          | Permissions::   |
                       +------v--+ +------v--+ +------v--+      | Policy          |
                       |Anthropic| | OpenAI  | |OAI-Compat|     +-----------------+
                       |Adapter  | |Adapter  | | Adapter  |
                       +---------+ +---------+ +----------+              |
                                                                +--------v--------+
                                                                | 32 Built-in     |
                                                                | Tools + MCP     |
                                                                +-----------------+
                                          |
                          +---------------+---------------+
                          |               |               |
                 +--------v------+ +------v------+ +------v--------+
                 | Context::     | | Hooks::     | | Observability:|
                 | Manager       | | Runner      | | BudgetEnforcer|
                 | (compaction)  | | (events)    | | CostCalculator|
                 +---------------+ +-------------+ +---------------+
                          |
                 +--------v--------+
                 | SQLite DB       |
                 | sessions        |
                 | messages        |
                 | memories        |
                 | cost_records    |
                 | tasks           |
                 | instincts       |
                 +-----------------+
```

---

## Infrastructure Modules

### CLI

Entry point for the gem. `CLI::App` parses ARGV and dispatches to one of five
modes: `:version`, `:auth`, `:help`, `:run`, or `:repl`. The REPL wires up
`InputHandler` for parsing, `Agent::Loop` for execution, and `Renderer` for output.
19 slash commands are registered in `Commands::Registry` with tab-completion
support.

Key classes: `App`, `REPL`, `InputHandler`, `Renderer`, `Spinner`,
`StreamFormatter`, `Setup`, `DaemonRunner`, `VersionCheck`.

### LLM Adapters

Faraday-based clients for multiple LLM providers. All adapters return the same
normalized types (`LLM::Response`, `TextBlock`, `ToolUseBlock`, `Usage`) regardless
of provider.

- **`Adapters::Anthropic`** -- Anthropic Claude (OAuth + API key, prompt caching,
  SSE streaming).
- **`Adapters::OpenAI`** -- OpenAI Chat Completions (Bearer auth, function calling,
  SSE streaming).
- **`Adapters::OpenAICompatible`** -- Inherits OpenAI, overrides base_url, provider
  name, models, and auth. Works with Groq, Together, Ollama, etc.
- **`LLM::Client`** -- Facade that delegates to the active adapter based on
  configuration.
- **`LLM::MessageBuilder`** -- Constructs the messages array for the API. Handles
  system prompt injection, tool result formatting, and context window limits.
- **`LLM::ModelRouter`** -- Routes model selection based on task context.

Supporting modules: `AnthropicStreaming`, `OpenAIStreaming`,
`OpenAIMessageTranslator`, `JsonParsing`, `PromptCaching`.

### Auth

OAuth PKCE flow with a three-level token fallback chain:
1. macOS Keychain (reads Claude Code's OAuth token)
2. Local YAML file (`~/.rubyn-code/tokens.yml`)
3. `ANTHROPIC_API_KEY` environment variable

Key classes: `OAuth`, `Server` (local WEBrick on port 19275), `TokenStore`.

### DB

SQLite persistence at `~/.rubyn-code/rubyn_code.db`. WAL mode, foreign keys
enabled. Sequential numbered migrations in `db/migrations/` (both `.sql` and `.rb`
formats). Tables: `schema_migrations`, `sessions`, `messages`, `tasks`,
`task_dependencies`, `memories`, `cost_records`, `hooks`, `skills_cache`,
`teammates`, `mailbox_messages`, `instincts`.

Key classes: `Connection` (singleton), `Migrator`, `Schema`.

### Config

Application settings with per-project overrides. Merges defaults with user
overrides from `~/.rubyn-code/config.yml` and project-level `.rubyn-code.yml`.
`Config::Defaults` holds frozen constants for all default values.
`Config::ProjectProfile` detects project characteristics (framework, test runner,
etc.) on first session start.

### Output

Terminal formatting utilities. `Formatter` handles general text/table formatting
with Pastel colors. `DiffRenderer` renders unified diffs with color highlighting
for `edit_file` and `review_pr` tools. `StreamFormatter` handles real-time LLM
streaming output with markdown buffering and Rouge syntax highlighting.

---

## Context Management: 3-Layer Compression

Rubyn Code uses a tiered approach to keep conversations within the LLM's context
window. Each layer is progressively more expensive:

### Layer 1: Micro-Compact (zero cost)

**When:** Context reaches 70% of threshold.
**What:** Replaces old tool result content with compact placeholders like
`[Previous: used read_file]`. Keeps the 2 most recent tool results intact.
**Cost:** Zero -- no LLM calls, pure string replacement.

### Layer 2: Context Collapse (zero cost)

**When:** Context exceeds threshold and micro-compact was insufficient.
**What:** Keeps the first message (initial user request) and the most recent 6
exchanges. Everything in between is replaced with a
`[N earlier messages snipped for context efficiency]` marker.
**Cost:** Zero -- no LLM calls, array slicing.

### Layer 3: Auto-Compact (LLM call)

**When:** Context still exceeds threshold after collapse.
**What:** Sends the conversation to a cheaper model (Claude Sonnet) for
summarization. The summary covers: what was accomplished, current state, and key
decisions. Replaces the entire conversation with the summary.
**Cost:** One LLM call to a cheaper model. Full transcript is saved to disk before
compaction.

Additionally, `DecisionCompactor` triggers compaction at logical boundaries (specs
passed, topic switch, multi-file edit complete) at a lower threshold (60%) to
prevent late-session context bloat.

---

## Token Efficiency Engine

Rubyn Code employs several strategies to reduce token usage and API costs:

### Dynamic Tool Schema Filtering

Instead of sending all 32+ tool schemas on every LLM call, `DynamicToolSchema`
detects the task context from the user's message and only includes relevant tools.
Base tools (read, write, edit, glob, grep, bash) are always included. Task-specific
tools are added based on keyword detection (e.g., "test" adds `run_specs`, "commit"
adds git tools). Previously discovered tools persist for the session. This reduces
per-turn system prompt overhead by 30-50%.

### Context Budget for Related Files

`ContextBudget` prioritizes which related files to load fully vs. as
signatures-only. It uses Rails convention-based priority (specs first, then
factories, services, models, etc.) and a configurable token budget (default: 4000
tokens). Files that exceed the remaining budget are loaded as extracted signatures
(class/module/method declarations only), typically 10-20% of original size.

### Schema Filtering

`SchemaFilter` extracts only relevant table definitions from `db/schema.rb` based
on which models are currently in context. For a large Rails app, this can reduce
schema context from 5-10K tokens to 200-500 tokens.

### Skill TTL and Size Caps

Skills loaded into context have a TTL (default: 5 turns). If a skill is not
referenced within its TTL, it is ejected. Skills are also capped at 800 tokens
(~3200 characters) -- longer skills are truncated.

### Prompt Caching

The Anthropic adapter supports prompt caching via `cache_control` injection. System
prompts and tool definitions are marked as cacheable, allowing the API to reuse
cached prefixes across turns. This significantly reduces input token costs for long
conversations.

### Tool Output Compression

`Tools::OutputCompressor` compresses large tool outputs before they enter the
conversation. `Tools::SpecOutputParser` extracts only relevant failure information
from test output, discarding passing test noise.
