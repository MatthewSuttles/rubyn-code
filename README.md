# Rubyn Code

An AI-powered CLI coding assistant built in Ruby, specialized for Ruby and Rails development. Powered by Claude Opus 4.6, authenticating via your existing Claude subscription (OAuth) — no API keys required.

## Quick Start

```bash
# Install the gem
gem install rubyn-code

# Start the interactive REPL
rubyn-code

# YOLO mode — no tool approval prompts
rubyn-code --yolo

# Run a single prompt and exit
rubyn-code -p "Add authentication to the users controller"
```

**Authentication:** Rubyn Code automatically reads your Claude Code OAuth token from the macOS Keychain. Just make sure you've logged into Claude Code at least once (`claude` in your terminal). No separate auth step needed.

## RUBYN.md — Project Instructions

Just like Claude Code has `CLAUDE.md`, Rubyn Code looks for instruction files to understand your project's conventions, preferences, and rules.

**Rubyn Code detects all three conventions:**
- `RUBYN.md` — Rubyn Code native
- `CLAUDE.md` — Claude Code compatible (works out of the box)
- `AGENT.md` — Generic agent convention

If your project already has a `CLAUDE.md` or `AGENT.md`, Rubyn Code will read it automatically. No migration needed.

```bash
# Create project instructions
cat > RUBYN.md << 'EOF'
# My Project

- Always use RSpec, never Minitest
- Use FactoryBot for test data
- Follow the service object pattern for business logic
- API endpoints use Grape, not Rails controllers
- Run rubocop before committing
EOF
```

### Where to put RUBYN.md

Rubyn Code loads `RUBYN.md` from multiple locations, all merged together:

| Location | Scope | Loaded |
|----------|-------|--------|
| `~/.rubyn-code/RUBYN.md` | Global | Always — applies to all projects |
| Parent directories above project root | Monorepo | Auto — walks up to find shared instructions |
| `./RUBYN.md` / `./CLAUDE.md` / `./AGENT.md` | Project | Auto — main project instructions |
| `./.rubyn-code/RUBYN.md` | Project | Auto — alternative location |
| `./subdir/RUBYN.md` (or CLAUDE.md, AGENT.md) | Subfolder | Auto — one level deep at startup |
| Any directory Rubyn navigates to | Dynamic | On demand — Rubyn checks when entering new dirs |

**Priority:** Project-level instructions override global ones. All files are concatenated into the system prompt.

### Example: Monorepo with multiple services

```
my-monorepo/
├── RUBYN.md              # Shared conventions (loaded for all services)
├── api/
│   ├── RUBYN.md          # API-specific: "Use Grape, JSON:API format"
│   └── ...
├── web/
│   ├── RUBYN.md          # Web-specific: "Use Hotwire, ViewComponents"
│   └── ...
└── workers/
    ├── RUBYN.md          # Worker-specific: "Use Sidekiq, idempotent jobs"
    └── ...
```

## Skills — 112 Ruby/Rails Best Practice Documents

Rubyn Code ships with 112 best practice documents organized by topic. Skills load **on-demand** — only their names appear in memory until Rubyn needs the full content.

### Built-in skill categories

| Category | Topics |
|----------|--------|
| **Ruby** | Collections, error handling, metaprogramming, concurrency |
| **Rails** | Controllers, models, views, migrations, ActiveRecord |
| **RSpec** | Matchers, factories, request specs, performance |
| **Minitest** | Assertions, system tests, fixtures |
| **Design Patterns** | Observer, strategy, decorator, builder, and more |
| **SOLID** | All five principles with Ruby examples |
| **Refactoring** | Extract method, replace conditional, code smells |
| **Code Quality** | Naming, YAGNI, value objects, null object |
| **Gems** | Development, versioning, publishing |
| **Sinatra** | Application structure, middleware, testing |

### Custom skills

Add your own skills or override built-in ones:

```bash
# Project-specific skills
mkdir -p .rubyn-code/skills
cat > .rubyn-code/skills/our_api_conventions.md << 'EOF'
# Our API Conventions

- All endpoints return JSON:API format
- Use Grape for API controllers
- Version APIs with /v1/ prefix
- Always paginate collections with Kaminari
EOF

# Global skills (apply to all projects)
mkdir -p ~/.rubyn-code/skills
cat > ~/.rubyn-code/skills/my_preferences.md << 'EOF'
# My Coding Preferences

- Use double quotes for strings
- Prefer guard clauses over nested conditionals
- Always add frozen_string_literal comment
EOF
```

**Skill priority:** Project `.rubyn-code/skills/` > User `~/.rubyn-code/skills/` > Bundled defaults

## PR Review — Best Practice Code Review

Rubyn Code can review your current branch against Ruby/Rails best practices, giving you line-by-line suggestions before you open a PR.

### Quick usage

```bash
rubyn > /review              # Review current branch vs main
rubyn > /review develop      # Review against develop branch
rubyn > /review main security  # Security-focused review only
```

### Focus areas

| Focus | What it checks |
|-------|---------------|
| `all` *(default)* | Everything — code quality, security, performance, testing, conventions |
| `security` | SQL injection, XSS, CSRF, mass assignment, auth gaps, sensitive data exposure |
| `performance` | N+1 queries, missing indexes, eager loading, caching, pagination |
| `style` | Ruby idioms, naming, method length, DRY violations, dead code |
| `testing` | Missing coverage, test quality, factory usage, edge cases, flaky test risks |

### What it does

1. Gets the diff of your current branch vs the base branch
2. Categorizes changed files (Ruby, templates, specs, migrations, config)
3. Loads relevant best practice skills automatically
4. Reviews every change with actionable suggestions
5. Rates each issue by severity:

| Severity | Meaning |
|----------|---------|
| **[critical]** | Must fix — security vulnerability, data loss risk, or broken functionality |
| **[warning]** | Should fix — performance issue, missing test, or convention violation |
| **[suggestion]** | Nice to have — cleaner approach, better naming, or Ruby idiom |
| **[nitpick]** | Optional — style preference or minor readability improvement |

### Example output

```
[warning] app/models/user.rb:15
  User.where(active: true).each { |u| u.posts.count }
  ↳ N+1 query — `posts.count` fires a separate query per user.
  Fix: User.where(active: true).includes(:posts).each { ... }
  Or use counter_cache: true on the association.

[critical] app/controllers/admin_controller.rb:8
  params[:user_id] used directly in SQL
  ↳ SQL injection risk. Use parameterized queries.
  Fix: User.where(id: params[:user_id])

[suggestion] app/services/create_order.rb:22
  Method `process` is 45 lines long
  ↳ Extract into smaller private methods for readability.
  Consider: extract_line_items, calculate_totals, apply_discounts
```

### Natural language works too

```bash
rubyn > Review my PR against best practices
rubyn > Check this branch for security issues
rubyn > Are there any N+1 queries in my changes?
```

## Architecture

Rubyn Code implements a 16-layer agentic architecture:

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 16: Continuous Learning (pattern extraction)           │
│  Layer 15: MCP (external tool servers via protocol)           │
│  Layer 14: Hooks & Events (pre/post tool interception)        │
│  Layer 13: Observability (cost tracking, token counting)      │
│  Layer 12: Memory (persistent knowledge across sessions)      │
│  Layer 11: Autonomous Operation (idle polling, KAIROS)        │
│  Layer 10: Protocols (shutdown handshake, plan approval)      │
│  Layer 9:  Teams (persistent teammates, mailbox messaging)    │
│  Layer 8:  Background Execution (async tasks, notifications)  │
│  Layer 7:  Task System (persistent DAG, dependencies)         │
│  Layer 6:  Sub-Agents (isolated context, summary return)      │
│  Layer 5:  Skills (112 Ruby/Rails best practice docs)         │
│  Layer 4:  Context Management (compression pipeline)          │
│  Layer 3:  Permissions (tiered access, deny lists)            │
│  Layer 2:  Tool System (28 tools, dispatch map)               │
│  Layer 1:  THE AGENT LOOP (while tool_use → execute → repeat) │
└──────────────────────────────────────────────────────────────┘
```

The core is six lines:

```ruby
while response.tool_use?
  results = execute_tools(response)
  conversation.add_tool_results(results)
  response = llm.chat(conversation.messages)
end
```

Everything else is a layer around that loop.

## Tools (28 built-in)

| Category | Tools |
|----------|-------|
| **File I/O** | `read_file`, `write_file`, `edit_file` |
| **Search** | `glob`, `grep` |
| **Execution** | `bash` (sandboxed, dangerous commands blocked) |
| **Web** | `web_search` (DuckDuckGo), `web_fetch` (fetch any URL as text) |
| **Git** | `git_status`, `git_diff`, `git_log`, `git_commit` |
| **Rails** | `rails_generate`, `db_migrate`, `run_specs`, `bundle_install`, `bundle_add` |
| **Review** | `review_pr` (diff-based best practice code review) |
| **Agents** | `spawn_agent` (isolated sub-agent), `spawn_teammate` (persistent named agent), `background_run` |
| **Agent** | `compact`, `load_skill`, `task` |
| **Memory** | `memory_search`, `memory_write` |
| **Teams** | `send_message`, `read_inbox` |

## CLI Commands

### Flags

```bash
rubyn-code                    # Start interactive REPL
rubyn-code --yolo             # Auto-approve all tool calls
rubyn-code -p "prompt"        # Run a single prompt and exit
rubyn-code --resume [ID]      # Resume a previous session
rubyn-code --auth             # Set up authentication
rubyn-code --version          # Show version
rubyn-code --help             # Show help
```

### Interactive Commands

Type `/` to see all available commands, or `/` + Tab for autocomplete:

```
/help              Show help
/quit              Exit Rubyn Code
/review [base]     PR review against best practices (default: main)
/spawn name role   Spawn a persistent teammate agent
/compact           Compress conversation context
/cost              Show token usage and costs
/clear             Clear the terminal
/undo              Remove last exchange
/tasks             List all tasks
/budget [amt]      Show or set session budget
/skill [name]      Load or list available skills
/resume [id]       Resume or list sessions
/version           Show version
```

### Tips

- Use `@filename` to include file contents in your message
- End a line with `\` for multiline input
- Ctrl-C once to interrupt, twice to exit
- `/` + Tab autocompletes slash commands

## Permission Modes

| Mode | Flag | Behavior |
|------|------|----------|
| **Allow Read** | *(default)* | Read tools auto-approved, writes need approval |
| **YOLO** | `--yolo` | Everything auto-approved — no prompts |

## Streaming Output

Rubyn Code streams responses in real-time — text appears character-by-character as the model generates it, just like Claude Code. No more waiting for the full response to render.

When Rubyn calls tools mid-response, you see each tool call and result live:

```
rubyn > Fix the N+1 query in UsersController
  > read_file: path=app/controllers/users_controller.rb
    class UsersController < ApplicationController...
  > edit_file: path=app/controllers/users_controller.rb, old_text=User.all, new_text=User.includes(:posts).all
    Edited app/controllers/users_controller.rb
  > run_specs: path=spec/controllers/users_controller_spec.rb
    3 examples, 0 failures

Fixed the N+1 by adding `.includes(:posts)` to the query. Specs pass. ✓
```

## Sub-Agents & Teams

### Sub-Agents (disposable)

Rubyn can spawn isolated sub-agents for research or parallel work. Sub-agents get their own fresh context and return only a summary — keeping Rubyn's main conversation clean.

```bash
rubyn > Go explore the app/services directory and summarize the patterns used

Spawning explore agent...
  > sub-agent > glob: pattern=app/services/**/*.rb
  > sub-agent > read_file: path=app/services/create_user.rb
  > sub-agent > read_file: path=app/services/process_payment.rb
Agent finished.

## Sub-Agent Result (explore)
The services directory uses a consistent .call pattern...
```

Two types:
- **Explore** (`agent_type: "explore"`) — read-only tools, for research
- **Worker** (`agent_type: "worker"`) — full write access, for doing work

### Teams (persistent)

Spawn named teammates that persist, have their own inbox, and communicate via messages:

```bash
rubyn > /spawn alice tester
Spawned teammate alice as tester

rubyn > Send alice a message to write specs for the User model
  > send_message: to=alice, content=Write specs for the User model...
```

Teammates run in background threads with their own agent loop, can claim tasks from the task board, and communicate via mailbox messaging.

## User Hooks

Customize Rubyn's behavior with `.rubyn-code/hooks.yml` in your project or `~/.rubyn-code/hooks.yml` globally:

```yaml
# Block dangerous operations
pre_tool_use:
  - tool: bash
    match: "rm -rf"
    action: deny
    reason: "Destructive recursive delete blocked"

  - tool: write_file
    path: "db/migrate/**"
    action: deny
    reason: "Use rails generate migration instead"

  - tool: bash
    match: "git push --force"
    action: deny
    reason: "Force push blocked — use regular push"

# Audit trail for file writes
post_tool_use:
  - tool: write_file
    action: log
  - tool: edit_file
    action: log
```

Hook actions:
- **`deny`** — block the tool call with a reason (shown to the model)
- **`log`** — append to `.rubyn-code/audit.log`

Matching:
- **`tool`** — exact tool name match
- **`match`** — string match anywhere in the parameters
- **`path`** — glob pattern match on the `path` parameter

## Continuous Learning

Rubyn learns from every session and gets smarter over time.

### How it works

1. **During conversation** — Rubyn saves preferences and patterns via `memory_write`
2. **On session end** — extracts reusable patterns ("instincts") with confidence scores
3. **On next startup** — injects top instincts and recent memories into the system prompt
4. **Over time** — unused instincts decay, reinforced ones strengthen

### Instinct lifecycle

```
Session 1: You correct Rubyn → instinct saved (confidence: 0.5)
Session 2: Same pattern confirmed → confidence: 0.7
Session 3: Not used → confidence: 0.65 (decay)
Session 4: Reinforced again → confidence: 0.8
Session 10: Never used again → deleted (below 0.05)
```

### Feedback reinforcement

Rubyn detects your feedback and adjusts:
- **"yes that fixed it"** / **"perfect"** → reinforces recent instincts
- **"no, use X instead"** / **"that's wrong"** → penalizes and learns the correction

## Web Tools

Rubyn can search the web and fetch documentation:

```bash
rubyn > Search for how to set up Sidekiq with Rails 8
  > web_search: query=Sidekiq Rails 8 setup guide

rubyn > Fetch the Sidekiq README
  > web_fetch: url=https://github.com/sidekiq/sidekiq/blob/main/README.md
```

### Search Providers

Rubyn auto-detects the best available search provider based on your environment variables. No configuration needed — just set the key and it switches automatically.

| Provider | Env Variable | Free Tier | Notes |
|----------|-------------|-----------|-------|
| **DuckDuckGo** | *(none needed)* | Unlimited | Default. No API key required |
| **Tavily** | `TAVILY_API_KEY` | 1,000/mo | Built for AI agents. Includes AI-generated answer |
| **Brave** | `BRAVE_API_KEY` | 2,000/mo | Fast, good quality results |
| **SerpAPI** | `SERPAPI_API_KEY` | 100/mo | Google results via API |
| **Google** | `GOOGLE_SEARCH_API_KEY` + `GOOGLE_SEARCH_CX` | 100/day | Official Google Custom Search |

**Priority order:** Tavily > Brave > SerpAPI > Google > DuckDuckGo

To switch providers, just export the key:

```bash
export TAVILY_API_KEY=tvly-xxxxxxxxxxxxx
rubyn-code  # Now uses Tavily automatically
```

## Git Integration

Full git workflow without leaving the REPL:

```bash
rubyn > What files have I changed?
  > git_status

rubyn > Show me the diff
  > git_diff: target=unstaged

rubyn > Commit these changes
  > git_commit: message=Fix N+1 query in UsersController, files=all

rubyn > Review my branch before I open a PR
  > /review
```

## Authentication

Rubyn Code uses your existing Claude subscription — no API keys needed.

### How it works

1. You log into Claude Code once (`claude` in terminal)
2. Rubyn Code reads the OAuth token from your macOS Keychain
3. It authenticates directly with the Anthropic API using your subscription

### Fallback chain

| Priority | Source | How |
|----------|--------|-----|
| 1 | macOS Keychain | Reads Claude Code's OAuth token automatically |
| 2 | `~/.rubyn-code/tokens.yml` | Manual token file |
| 3 | `ANTHROPIC_API_KEY` env var | Standard API key (pay-per-use) |

### Supported plans

Works with Claude Pro, Max, Team, and Enterprise subscriptions. Default model: **Claude Opus 4.6**.

## Context Compression

Three-layer pipeline for infinite sessions:

1. **Micro Compact** — runs every turn, replaces old tool results with placeholders (zero cost)
2. **Auto Compact** — triggers at 50K tokens, saves transcript to disk, LLM-summarizes
3. **Manual Compact** — `/compact` at strategic moments (between phases of work)

## Task System

SQLite-backed DAG with dependency resolution:

```
Task 1: Set up database schema
Task 2: Build API endpoints      (blocked by: Task 1)
Task 3: Write integration tests  (blocked by: Task 2)
```

## Memory

Three-tier persistence with full-text search:

- **Short-term** — current session
- **Medium-term** — per-project (`.rubyn-code/`)
- **Long-term** — global (`~/.rubyn-code/`)

## MCP Support

Connect external tool servers via Model Context Protocol:

```json
// .rubyn-code/mcp.json
{
  "servers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@anthropic/github-mcp-server"]
    }
  }
}
```

## Configuration

### Global config

`~/.rubyn-code/config.yml`:

```yaml
model: claude-opus-4-6
permission_mode: allow_read
session_budget: 5.00
daily_budget: 10.00
max_iterations: 200
```

### Project config

`.rubyn-code/config.yml` (overrides global):

```yaml
model: claude-sonnet-4-6
permission_mode: autonomous
```

## Data Storage

All data stored locally in SQLite:

| Location | Purpose |
|----------|---------|
| `~/.rubyn-code/config.yml` | Global settings |
| `~/.rubyn-code/tokens.yml` | Auth tokens (0600 permissions) |
| `~/.rubyn-code/rubyn_code.db` | Sessions, tasks, memories, costs |
| `~/.rubyn-code/RUBYN.md` | Global project instructions |
| `~/.rubyn-code/skills/*.md` | Global custom skills |
| `.rubyn-code/config.yml` | Project settings |
| `.rubyn-code/skills/*.md` | Project custom skills |
| `RUBYN.md` | Project instructions |

## Development

```bash
# Run tests
bundle exec rspec

# Run a specific test
bundle exec rspec spec/rubyn_code/agent/loop_spec.rb

# Interactive console
ruby -Ilib bin/console
```

## Project Structure

```
rubyn-code/
├── exe/rubyn-code              # CLI entry point
├── lib/rubyn_code/
│   ├── agent/                  # Layer 1: Core agent loop
│   ├── tools/                  # Layer 2: 18 tool implementations
│   ├── permissions/            # Layer 3: Tiered access control
│   ├── context/                # Layer 4: Compression pipeline
│   ├── skills/                 # Layer 5: Skill loader
│   ├── sub_agents/             # Layer 6: Isolated child agents
│   ├── tasks/                  # Layer 7: Task DAG
│   ├── background/             # Layer 8: Async execution
│   ├── teams/                  # Layer 9: Agent teams
│   ├── protocols/              # Layer 10: Coordination
│   ├── autonomous/             # Layer 11: KAIROS daemon
│   ├── memory/                 # Layer 12: Persistence
│   ├── observability/          # Layer 13: Cost tracking
│   ├── hooks/                  # Layer 14: Event system
│   ├── mcp/                    # Layer 15: MCP client
│   ├── learning/               # Layer 16: Continuous learning
│   ├── llm/                    # Claude API client (OAuth + API key)
│   ├── auth/                   # Token management (Keychain + file + env)
│   ├── db/                     # SQLite connection & migrations
│   ├── cli/                    # REPL, input handling, rendering
│   └── config/                 # Settings management
├── skills/                     # 112 Ruby/Rails best practice docs
│   ├── ruby/                   # Ruby language patterns
│   ├── rails/                  # Rails framework conventions
│   ├── rspec/                  # RSpec testing patterns
│   ├── design_patterns/        # GoF and Ruby patterns
│   ├── solid/                  # SOLID principles
│   ├── refactoring/            # Refactoring techniques
│   └── ...                     # + code_quality, gems, minitest, sinatra
├── db/migrations/              # 11 SQL migration files
└── spec/                       # 48 RSpec test files (314 examples)
```

## License

MIT
