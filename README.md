<p align="center">
  <img src="docs/RubynLogo.png" alt="Rubyn Code" width="200">
</p>

<h1 align="center">Rubyn Code</h1>

<p align="center">
  <strong>AI Code Assistant for Ruby & Rails — Open Source</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/rubyn-code"><img src="https://badge.fury.io/rb/rubyn-code.svg" alt="Gem Version"></a>
  <a href="https://github.com/rubocop/rubocop"><img src="https://img.shields.io/badge/code_style-rubocop-brightgreen.svg" alt="Ruby Style Guide"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <a href="https://github.com/MatthewSuttles/rubyn-code/actions/workflows/ci.yml"><img src="https://github.com/MatthewSuttles/rubyn-code/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

Refactor controllers, generate idiomatic RSpec, catch N+1 queries, review code for anti-patterns, and build entire features — all context-aware with your schema, routes, and specs. Powered by Claude Opus 4.6, running on your existing Claude subscription.

<img width="1230" height="280" alt="image" src="https://github.com/user-attachments/assets/14e07ce8-def0-4a8f-ac89-46661361a4eb" />


> **Rubyn is going open source.** The original [Rubyn gem](https://github.com/Rubyn-AI/rubyn) provided AI-assisted refactoring, spec generation, and code review through the Rubyn API. **Rubyn Code** is the next evolution — a complete agentic coding assistant that runs locally, thinks for itself, and learns from every session. No API keys. No separate billing. Just `gem install rubyn-code` and go.

## Why Rubyn?

- **Rails-native** — understands service object extraction, RSpec conventions, ActiveRecord patterns, and Hotwire
- **Context-aware** — automatically incorporates schema, routes, specs, factories, and models
- **Best practices built in** — ships with 112 curated Ruby and Rails guidelines that load on demand
- **Agentic** — doesn't just answer questions. Reads files, writes code, runs specs, commits, reviews PRs, spawns sub-agents, and remembers what it learns

## Install

Requires **Ruby 4.0+**. Install with your latest Ruby, then pin it so it works in every project:

```bash
# Install the gem
gem install rubyn-code

# Pin to this Ruby — bypasses rbenv/rvm version switching
rubyn-code --setup
```

That's it. `rubyn-code` now works in any project regardless of `.ruby-version`.

<details>
<summary>Using rbenv?</summary>

If you manage multiple Rubies with rbenv, install on your latest:

```bash
RBENV_VERSION=4.0.2 gem install rubyn-code
RBENV_VERSION=4.0.2 rubyn-code --setup
```

The `--setup` command creates a launcher in `~/.local/bin` that calls the gem wrapper directly, skipping rbenv's shim. As long as `~/.local/bin` is in your PATH before `~/.rbenv/shims`, you're good.

</details>

<details>
<summary>Using rvm?</summary>

```bash
rvm use 4.0.2
gem install rubyn-code
rubyn-code --setup
```

</details>

<details>
<summary>From source</summary>

```bash
git clone https://github.com/MatthewSuttles/rubyn-code.git
cd rubyn-code
bundle install
bundle exec ruby -Ilib exe/rubyn-code
```

</details>

**Authentication:** Rubyn Code reads your Claude Code OAuth token from the macOS Keychain automatically. Just make sure you've logged into Claude Code once (`claude` in your terminal). Also supports `ANTHROPIC_API_KEY` env var. See [Authentication](#authentication) for OpenAI and other providers.

## Quick Start

```bash
# Interactive REPL
rubyn-code

# YOLO mode — no tool approval prompts
rubyn-code --yolo

# Single prompt
rubyn-code -p "Refactor app/controllers/orders_controller.rb into service objects"
```

## What Can Rubyn Do?

### Refactor code
```
rubyn > This orders controller is 300 lines. Break it up.
  > read_file: path=app/controllers/orders_controller.rb
  > read_file: path=app/models/order.rb
  > read_file: path=config/routes.rb
  > write_file: path=app/services/orders/create_service.rb
  > write_file: path=app/services/orders/cancel_service.rb
  > edit_file: path=app/controllers/orders_controller.rb

Done. Extracted CreateService and CancelService. Controller is down to 45 lines.
```

### Generate specs
```
rubyn > Write specs for the new service objects
  > read_file: path=app/services/orders/create_service.rb
  > read_file: path=spec/factories/orders.rb
  > write_file: path=spec/services/orders/create_service_spec.rb
  > run_specs: path=spec/services/orders/

4 examples, 0 failures. All green. ✓
```

### Review code
```
rubyn > /review
  > review_pr: base_branch=main

[warning] app/models/user.rb:15 — N+1 query detected
[critical] app/controllers/admin_controller.rb:8 — SQL injection risk
[suggestion] app/services/create_order.rb:22 — Method too long, extract private methods
```

### Explore codebases
```
rubyn > I'm new to this project. Give me the lay of the land.

Spawning explore agent...
[⠹] Agent exploring the codebase... (23 tools)
Agent finished (23 tool calls).

This is a Rails 7.1 e-commerce app with...
```

## 29 Built-in Tools

| Category | Tools |
|----------|-------|
| **File I/O** | `read_file`, `write_file`, `edit_file` |
| **Search** | `glob`, `grep` |
| **Execution** | `bash` (sandboxed, dangerous commands blocked) |
| **Web** | `web_search`, `web_fetch` |
| **Git** | `git_status`, `git_diff`, `git_log`, `git_commit` |
| **Rails** | `rails_generate`, `db_migrate`, `run_specs`, `bundle_install`, `bundle_add` |
| **Review** | `review_pr` (diff-based best practice code review) |
| **Agents** | `spawn_agent`, `spawn_teammate`, `background_run` |
| **Context** | `compact`, `load_skill`, `task` |
| **Memory** | `memory_search`, `memory_write` |
| **Teams** | `send_message`, `read_inbox` |
| **Interactive** | `ask_user` (ask clarifying questions mid-task) |

## 112 Best Practice Skills

Rubyn ships with curated best practice documents that load on demand. Only skill names are in memory — full content loads when Rubyn needs it.

| Category | Topics |
|----------|--------|
| **Ruby** | Collections, error handling, metaprogramming, concurrency, pattern matching |
| **Rails** | Controllers, models, views, migrations, ActiveRecord, Hotwire, caching, security |
| **RSpec** | Matchers, factories, request specs, shared examples, performance |
| **Minitest** | Assertions, system tests, fixtures, mocking |
| **Design Patterns** | Observer, strategy, decorator, builder, factory, adapter, and more |
| **SOLID** | All five principles with Ruby examples |
| **Refactoring** | Extract method/class, replace conditional, code smells, command-query separation |
| **Code Quality** | Naming, YAGNI, value objects, null object, technical debt |
| **Gems** | Sidekiq, Devise, FactoryBot, Pundit, Faraday, Stripe, RuboCop, dry-rb |
| **Sinatra** | Application structure, middleware, testing |

### Custom skills

Override or extend with your own:

```bash
# Project-specific
mkdir -p .rubyn-code/skills
echo "# Always use Grape for APIs" > .rubyn-code/skills/api_conventions.md

# Global
mkdir -p ~/.rubyn-code/skills
echo "# Use double quotes for strings" > ~/.rubyn-code/skills/my_style.md
```

## Context Architecture

Rubyn automatically loads relevant context based on what you're working on:

- **Controllers** → includes models, routes, request specs, services
- **Models** → includes schema, associations, specs, factories
- **Service objects** → includes referenced models and their specs
- **Any file** → checks for `RUBYN.md`, `CLAUDE.md`, or `AGENT.md` instructions

## RUBYN.md — Project Instructions

Drop a `RUBYN.md` in your project root and Rubyn follows your conventions:

```markdown
# My Project

- Always use RSpec, never Minitest
- Use FactoryBot for test data
- Service objects go in app/services/ with a .call interface
- API endpoints use Grape, not Rails controllers
- Run rubocop before committing
```

Also reads `CLAUDE.md` and `AGENT.md` — no migration needed from other tools.

| Location | Scope |
|----------|-------|
| `~/.rubyn-code/RUBYN.md` | Global — all projects |
| Parent directories | Monorepo — shared conventions |
| `./RUBYN.md` | Project root |
| `./subdir/RUBYN.md` | Subfolder-specific |

## PR Review

Review your branch against best practices before opening a PR:

```
rubyn > /review              # vs main
rubyn > /review develop      # vs develop
rubyn > /review main security  # security focus only
```

Focus areas: `all`, `security`, `performance`, `style`, `testing`

Severity ratings: **[critical]** **[warning]** **[suggestion]** **[nitpick]**

## Sub-Agents & Teams

### Sub-Agents (disposable)
```
rubyn > Explore the app/services directory and summarize the patterns

Spawning explore agent...
[⠹] Dispatching the intern... (18 tools)
Agent finished (18 tool calls).
```

Two types: **explore** (read-only) and **worker** (full write access).

### Teams (persistent)
```
rubyn > /spawn alice tester
Spawned teammate alice as tester

rubyn > Send alice a message to write specs for the User model
```

Teammates run in background threads with their own agent loop and mailbox.

## Continuous Learning

Rubyn gets smarter with every session:

1. **During conversation** — saves preferences and patterns to memory
2. **On session end** — extracts reusable "instincts" with confidence scores
3. **On next startup** — injects top instincts into the system prompt
4. **Over time** — reinforced instincts strengthen, unused ones decay and get pruned

## Streaming Output

Real-time streaming with live syntax highlighting via Rouge/Monokai. Code blocks are buffered and highlighted when complete. No waiting for full responses.

## Search Providers

Auto-detects the best available provider:

| Provider | Env Variable | Free Tier |
|----------|-------------|-----------|
| **DuckDuckGo** | *(none)* | Unlimited |
| **Tavily** | `TAVILY_API_KEY` | 1,000/mo |
| **Brave** | `BRAVE_API_KEY` | 2,000/mo |
| **SerpAPI** | `SERPAPI_API_KEY` | 100/mo |
| **Google** | `GOOGLE_SEARCH_API_KEY` + `GOOGLE_SEARCH_CX` | 100/day |

## User Hooks

Customize behavior via `.rubyn-code/hooks.yml`:

```yaml
pre_tool_use:
  - tool: bash
    match: "rm -rf"
    action: deny
    reason: "Destructive delete blocked"
  - tool: write_file
    path: "db/migrate/**"
    action: deny
    reason: "Use rails generate migration"

post_tool_use:
  - tool: write_file
    action: log
```

## CLI Reference

```bash
rubyn-code                    # Interactive REPL
rubyn-code --yolo             # Auto-approve all tools
rubyn-code -p "prompt"        # Single prompt, exit when done
rubyn-code --resume [ID]      # Resume previous session
rubyn-code --setup            # Pin to this Ruby (run once after install)
rubyn-code --debug            # Enable debug output
rubyn-code --auth             # Authenticate with Claude
rubyn-code --version          # Show version
rubyn-code --help             # Show help
```

### Slash Commands

| Command | Purpose |
|---------|---------|
| `/help` | Show help |
| `/quit` | Exit (saves session + extracts learnings) |
| `/new` | Save session and start a fresh conversation |
| `/review [base]` | PR review against best practices |
| `/spawn name role` | Spawn a persistent teammate |
| `/compact` | Compress conversation context |
| `/cost` | Show token usage and costs |
| `/tasks` | List all tasks |
| `/budget [amt]` | Show or set session budget |
| `/skill [name]` | Load or list available skills |
| `/resume [id]` | Resume or list sessions |
| `/provider` | Add or list providers |
| `/model` | Show/switch model and provider |

## Authentication

### Anthropic (default)

| Priority | Source | Setup |
|----------|--------|-------|
| 1 | macOS Keychain | Log into Claude Code once: `claude` |
| 2 | Token file | `~/.rubyn-code/tokens.yml` |
| 3 | Environment | `export ANTHROPIC_API_KEY=sk-ant-...` |

Works with Claude Pro, Max, Team, and Enterprise. Default model: **Claude Opus 4.6**.

### OpenAI

```bash
export OPENAI_API_KEY=sk-...
```

Available models: `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-4o`, `gpt-4o-mini`, `o3`, `o4-mini`

### Other Providers (Groq, Together, Ollama, etc.)

Set the API key as an environment variable in your shell profile (`~/.zshrc`, `~/.bashrc`):

```bash
export GROQ_API_KEY=gsk-...
export TOGETHER_API_KEY=...
```

The env var name comes from the `env_key` field in your config. If omitted, Rubyn derives it
from the provider name: `<PROVIDER>_API_KEY` (uppercased, hyphens become underscores).
For example, provider `bedrock-proxy` looks for `BEDROCK_PROXY_API_KEY`.

Add providers interactively or via config:

```bash
# Via slash command
/provider add groq https://api.groq.com/openai/v1 --env-key GROQ_API_KEY --models llama-3.3-70b

# For Anthropic-format proxies (e.g., Bedrock, custom proxies)
/provider add my-proxy https://proxy.example.com/v1 --format anthropic --env-key PROXY_API_KEY --models claude-sonnet-4-6

# List configured providers
/provider list
```

Or add directly to `~/.rubyn-code/config.yml`:

```yaml
providers:
  groq:
    base_url: https://api.groq.com/openai/v1
    env_key: GROQ_API_KEY
    models:
      top: llama-3.3-70b
  my-proxy:
    api_format: anthropic        # 'openai' (default) or 'anthropic'
    base_url: https://proxy.example.com/v1
    env_key: PROXY_API_KEY
    models:
      top: claude-sonnet-4-6
```

Then switch with `/model groq:llama-3.3-70b`.

Local providers (Ollama, LM Studio) running on `localhost`/`127.0.0.1` don't require an API key.

## Architecture

16-layer agentic architecture:

```
┌──────────────────────────────────────────────────────────────┐
│  Layer 16: Continuous Learning (pattern extraction + decay)   │
│  Layer 15: MCP (external tool servers via protocol)           │
│  Layer 14: Hooks & Events (user-configurable pre/post hooks) │
│  Layer 13: Observability (cost tracking, budget enforcement)  │
│  Layer 12: Memory (persistent knowledge across sessions)      │
│  Layer 11: Autonomous Operation (GOLEM daemon, task claiming) │
│  Layer 10: Protocols (shutdown handshake, plan approval)      │
│  Layer 9:  Teams (persistent teammates, mailbox messaging)    │
│  Layer 8:  Background Execution (async tasks, notifications)  │
│  Layer 7:  Task System (persistent DAG with dependencies)     │
│  Layer 6:  Sub-Agents (explore + worker, isolated contexts)   │
│  Layer 5:  Skills (112 best practice docs, on-demand loading) │
│  Layer 4:  Context Management (3-layer compression pipeline)  │
│  Layer 3:  Permissions (tiered access + deny lists + hooks)   │
│  Layer 2:  Tool System (29 tools, dispatch map registry)      │
│  Layer 1:  THE AGENT LOOP (while tool_use → execute → repeat) │
└──────────────────────────────────────────────────────────────┘
```

## Configuration

```yaml
# ~/.rubyn-code/config.yml (global)
model: claude-opus-4-6
permission_mode: allow_read
session_budget: 5.00
daily_budget: 10.00

# .rubyn-code/config.yml (project — overrides global)
model: claude-sonnet-4-6
permission_mode: autonomous

# Use OpenAI instead of Anthropic
# provider: openai
# model: gpt-4o

# Use a custom provider (add via /provider add or under providers: key)
# provider: groq
# model: llama-3.3-70b
```

### Multi-Provider Model Routing

Rubyn can automatically route tasks to different AI models based on complexity. Simple tasks (file search, git ops) use cheap, fast models. Complex tasks (architecture, security review) use the most capable model. Configure per-provider model tiers in `config.yml`:

```yaml
# ~/.rubyn-code/config.yml
provider: anthropic
model: claude-opus-4-6

providers:
  anthropic:
    env_key: ANTHROPIC_API_KEY
    models:
      cheap: claude-haiku-4-5      # file search, git ops, formatting
      mid: claude-sonnet-4-6       # code gen, specs, refactors, reviews
      top: claude-opus-4-6         # architecture, security, complex work

  openai:
    env_key: OPENAI_API_KEY
    models:
      cheap: gpt-5.4-nano          # lightweight tasks
      mid: gpt-5.4-mini            # regular coding
      top: gpt-5.4                 # complex reasoning

  groq:
    base_url: https://api.groq.com/openai/v1
    env_key: GROQ_API_KEY
    models:
      cheap: llama-3-8b
      mid: llama-3-70b
    pricing:
      llama-3-8b: [0.05, 0.08]    # [input_rate, output_rate] per million tokens
      llama-3-70b: [0.59, 0.79]

  ollama:
    base_url: http://localhost:11434/v1
    models:
      cheap: llama3
      mid: llama3
      top: llama3
```

**How it works:** When you ask Rubyn to do something, the Model Router detects the task type and picks the right tier. If you've configured model tiers for a provider, those are used first. Otherwise it falls back to the built-in defaults (Anthropic for all tiers).

| Tier | Task types | Default model |
|------|-----------|---------------|
| **cheap** | File search, git ops, formatting, summaries | `claude-haiku-4-5` |
| **mid** | Code generation, specs, refactors, code review, bug fixes | `claude-sonnet-4-6` |
| **top** | Architecture, security review, complex refactors, planning | `claude-opus-4-6` |

You can also set custom pricing per model so `/cost` reports accurate spending for third-party providers.

## Development

Requires Ruby 4.0+.

```bash
git clone https://github.com/MatthewSuttles/rubyn-code.git
cd rubyn-code
bundle install
bundle exec rspec
```

## From Rubyn to Rubyn Code

If you used the original [Rubyn gem](https://github.com/Rubyn-AI/rubyn), here's what changed:

| Rubyn (original) | Rubyn Code (open source) |
|-------------------|--------------------------|
| Rubyn API required | Runs locally, no external API |
| API key billing | Uses your Claude subscription |
| Refactor, spec, review commands | Full agentic assistant — reads, writes, thinks, learns |
| Static best practices | 112 on-demand skills + custom overrides |
| Single-turn commands | Multi-turn sessions with memory and context |
| Closed source | **MIT open source** |

## Contributing

PRs welcome. If your team has conventions that should be a skill document, contribute it. If you need a tool we don't have, the tool system is a base class and a registry — add yours.

```bash
# Add a new tool
lib/rubyn_code/tools/your_tool.rb  # extend Base, register with Registry

# Add a new skill
skills/your_category/your_skill.md  # markdown with optional YAML frontmatter
```

## License

MIT License — see [LICENSE](LICENSE) for details.
