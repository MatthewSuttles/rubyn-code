# CLI::Commands — Slash Command System

> Registry-based command dispatch for the REPL. Same Base/Registry pattern as the tool system.

## Architecture

```
User types /help
    ↓
InputHandler.classify → :command
    ↓
REPL#handle_command
    ↓
Registry#dispatch('/help', args, context)
    ↓
Help#execute(args, context)
    ↓
(optional) → action hash back to REPL for state changes
```

### Core Infrastructure

| File | Class | Purpose |
|------|-------|---------|
| `base.rb` | `Base` | Abstract command — `command_name`, `description`, `aliases`, `execute(args, ctx)` |
| `registry.rb` | `Registry` | Discovers, registers, dispatches commands. Provides tab-completion list |
| `context.rb` | `Context` | `Data.define` value object with all deps a command needs |

### Context Object

`Context` is a frozen `Data.define` carrying everything a command might need:

```ruby
Context = Data.define(
  :renderer, :conversation, :agent_loop, :context_manager,
  :budget_enforcer, :llm_client, :db, :session_id,
  :project_root, :skill_loader, :session_persistence,
  :background_worker, :permission_tier, :plan_mode
)
```

Commands receive it as the second argument to `execute`. Never mutate it — use
`with_message_handler` to attach a message callback if the command needs to send
prompts back to the agent loop.

## Commands

| Command | File | Description |
|---------|------|-------------|
| `/budget` | `budget.rb` | Show or set session budget (/budget [amount]) |
| `/clear` | `clear.rb` | Clear the terminal |
| `/compact` | `compact.rb` | Compress conversation context |
| `/context` | `context_info.rb` | Show context window usage |
| `/cost` | `cost.rb` | Show token usage and costs |
| `/diff` | `diff.rb` | Show git diff (staged, unstaged, or vs branch) |
| `/doctor` | `doctor.rb` | Environment health check |
| `/help` | `help.rb` | Show this help message |
| `/model` | `model.rb` | Show or switch model (/model [name]) |
| `/plan` | `plan.rb` | Toggle plan mode (think before acting) |
| `/quit` | `quit.rb` | Exit Rubyn Code (aliases: `/exit`, `/q`) |
| `/resume` | `resume.rb` | Resume a session or list recent sessions |
| `/review` | `review.rb` | Review current branch against best practices |
| `/skill` | `skill.rb` | Load a skill or list available skills |
| `/spawn` | `spawn.rb` | Spawn a teammate agent (/spawn \<name\> [role]) |
| `/tasks` | `tasks.rb` | List all tasks |
| `/tokens` | `tokens.rb` | Show token usage and context window estimate |
| `/undo` | `undo.rb` | Remove last exchange |
| `/version` | `version.rb` | Show version info |

## Action Hashes

Some commands can't change REPL state directly (they don't have access to the loop
or session). Instead, they return an **action hash** that the REPL processes:

```ruby
# Plan mode toggle
{ action: :set_plan_mode, enabled: true }

# Model switch
{ action: :set_model, model: 'claude-sonnet-4-20250514' }

# Budget update
{ action: :set_budget, amount: 10.0 }

# Spawn teammate
{ action: :spawn_teammate, name: 'alice', role: 'coder' }

# Resume session
{ action: :set_session_id, session_id: 'abc123' }
```

The REPL's `handle_command` method pattern-matches on these and applies the state change.

## Adding a New Command

1. Create `lib/rubyn_code/cli/commands/my_command.rb`
2. Inherit from `Base`, define `command_name` (with `/` prefix), `description`, `execute`
3. Add autoload entry in `lib/rubyn_code.rb` under `module Commands`
4. Register it in `REPL#setup_command_registry!`
5. Add spec in `spec/rubyn_code/cli/commands/my_command_spec.rb`

```ruby
# frozen_string_literal: true

module RubynCode
  module CLI
    module Commands
      class MyCommand < Base
        def self.command_name = '/mycommand'
        def self.description = 'Does a thing'

        def execute(args, ctx)
          ctx.renderer.info('Did the thing!')
        end
      end
    end
  end
end
```

## Plan Mode

`/plan` toggles plan mode via an action hash. When enabled:

- `Agent::Loop` sends only **read-only tools** (risk level `:read`) to Claude
- Claude can read files, grep, glob, check git status/log/diff — full exploration
- Claude **cannot** write, edit, execute, or modify anything
- A plan-mode system prompt is injected reinforcing these boundaries
- Claude responds with analysis, proposed steps, and gathered context
- Toggle off with `/plan` again to resume normal execution

Read-only tools in plan mode: `read_file`, `grep`, `glob`, `git_diff`, `git_log`,
`git_status`, `review_pr`, `memory_search`, `web_search`, `web_fetch`
