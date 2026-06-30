# Hooks Reference

## What Are Hooks?

Hooks are event-driven callbacks that fire at key points during the agent's
execution. They let you extend, observe, and control Rubyn Code's behavior without
modifying core code. Hooks can:

- **Deny** tool calls before they execute (security, policy enforcement)
- **Transform** tool output after execution (filtering, redaction)
- **Log** events for auditing or debugging
- **Track** costs and usage automatically
- **Trigger** compaction or other maintenance tasks

Hooks are registered on a thread-safe `Hooks::Registry` and executed by
`Hooks::Runner`. Each hook is a callable object (anything responding to `#call`)
with an optional priority. Lower priority numbers run first.

---

## Event Types

The following events are supported (defined in `Hooks::Registry::VALID_EVENTS`):

| Event | When It Fires | Context Keys | Special Semantics |
|-------|---------------|--------------|-------------------|
| `pre_tool_use` | Before a tool executes | `tool_name:`, `tool_input:` | Return `{ deny: true, reason: "..." }` to block |
| `post_tool_use` | After a tool executes | `tool_name:`, `tool_input:`, `result:` | Return value replaces output (pipeline) |
| `pre_llm_call` | Before an LLM API call | Varies by caller | Generic (return value ignored) |
| `post_llm_call` | After an LLM API call | `response:`, `conversation:`, `context_manager:`, `budget_enforcer:` | Generic (return value ignored) |
| `on_stall` | When the loop detector triggers | Varies | Generic (return value ignored) |
| `on_error` | When an error occurs | Varies | Generic (return value ignored) |
| `on_session_end` | When a session ends | Varies | Generic (return value ignored) |

### Event Semantics

**`pre_tool_use` (deny gating):** Hooks run in priority order. If any hook returns
a hash with `{ deny: true }`, execution stops immediately and the tool call is
blocked. The optional `reason` field is reported back to the LLM. Remaining hooks
are skipped.

**`post_tool_use` (output pipeline):** Hooks run in priority order. Each hook
receives the output from the previous hook (or the original result). A hook can
transform the output by returning a new value, or return `nil` to pass through
unchanged. This enables chaining transformations.

**All other events (generic):** Hooks run in priority order. Return values are
ignored. Exceptions are caught and logged -- they never crash the agent.

---

## Hook Configuration Format (YAML)

User hooks are configured in YAML files. Rubyn Code checks two locations in order:

1. **Project-level:** `.rubyn-code/hooks.yml` (in the project root)
2. **Global:** `~/.rubyn-code/hooks.yml`

Both files are loaded if they exist. Project hooks and global hooks are merged.

### YAML Structure

```yaml
# .rubyn-code/hooks.yml

pre_tool_use:
  - tool: bash
    match: "rm -rf"
    action: deny
    reason: "Destructive delete blocked by project policy"

  - tool: write_file
    path: "db/migrate/**"
    action: deny
    reason: "Use 'rails generate migration' instead of writing migration files directly"

  - tool: bash
    match: "git push --force"
    action: deny
    reason: "Force push is not allowed"

post_tool_use:
  - tool: write_file
    action: log

  - tool: bash
    action: log
```

### Configuration Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `tool` | String | No | Tool name to match (e.g. `bash`, `write_file`). Omit to match all tools. |
| `match` | String | No | Substring match against the tool's input parameters (stringified). |
| `path` | String | No | Glob pattern matched against the `path` parameter (using `File.fnmatch?`). |
| `action` | String | Yes | What to do: `deny` or `log`. |
| `reason` | String | No | Human-readable reason shown when a tool call is denied. |

---

## Match Patterns

Hooks use three matching mechanisms, all of which must pass for the hook to fire:

### Tool Name Match

```yaml
tool: bash  # Only matches the 'bash' tool
```

If `tool` is omitted, the hook matches all tools.

### Substring Match

```yaml
match: "rm -rf"  # Matches if the tool's parameters (as a string) contain "rm -rf"
```

The `match` field checks whether the stringified tool input includes the given
substring. This is useful for catching dangerous commands regardless of their full
argument list.

### Path Glob Match

```yaml
path: "db/migrate/**"  # Matches if the tool's 'path' parameter matches this glob
```

The `path` field uses `File.fnmatch?` for glob matching against the tool's `path`
parameter. Supports `*` (single segment), `**` (recursive), and `?` (single
character) wildcards.

### Combined Matching

All specified fields must match. This provides AND logic:

```yaml
- tool: write_file
  path: "config/**"
  action: deny
  reason: "Config files are read-only in this project"
```

This only denies `write_file` calls where the path matches `config/**`.

---

## Action Types

### deny

Blocks the tool call before it executes. The LLM receives the denial reason and
can adjust its approach.

```yaml
pre_tool_use:
  - tool: bash
    match: "DROP TABLE"
    action: deny
    reason: "SQL DROP TABLE commands are prohibited"
```

Only valid for `pre_tool_use` events.

### log

Writes an audit log entry to `.rubyn-code/audit.log` with a timestamp, tool name,
and truncated result (first 200 characters).

```yaml
post_tool_use:
  - tool: write_file
    action: log
```

Log entries look like:
```
[2026-04-08 14:30:22 -0500] write_file: Successfully wrote 42 lines to app/models/user.rb
```

Only valid for `post_tool_use` events.

---

## Built-in Hooks

Rubyn Code ships with three built-in hooks registered automatically at startup via
`Hooks::BuiltIn.register_all!`:

### CostTrackingHook (priority: 10)

**Event:** `post_llm_call`

Records token usage and cost after every LLM API call. Extracts `input_tokens`,
`output_tokens`, `cache_read_input_tokens`, and `cache_creation_input_tokens` from
the response usage data and passes them to the `BudgetEnforcer` for tracking.

### LoggingHook (priority: 50)

**Events:** `pre_tool_use` and `post_tool_use`

Logs tool calls and their results through the `Output::Formatter`. On
`pre_tool_use`, logs the tool name and input arguments. On `post_tool_use`, logs
the tool result. This is what produces the tool call/result display in the
terminal.

### AutoCompactHook (priority: 90)

**Event:** `post_llm_call`

Triggers a compaction check via `Context::Manager#auto_compact` after each LLM
call to keep the context window within bounds.

---

## Programmatic Hook Registration

Hooks can also be registered programmatically in Ruby code:

```ruby
# Register a block as a hook
registry = RubynCode::Hooks::Registry.new

registry.on(:pre_tool_use, priority: 20) do |tool_name:, tool_input:, **|
  if tool_name == 'bash' && tool_input.to_s.include?('sudo')
    { deny: true, reason: 'sudo commands are not allowed' }
  end
end

# Register a callable object
class MyCustomHook
  def call(tool_name:, result:, **)
    # Transform or log the result
    result
  end
end

registry.on(:post_tool_use, MyCustomHook.new, priority: 75)
```

### Registry API

```ruby
# Register a hook
registry.on(event, callable = nil, priority: 100, &block)

# Get hooks for an event (sorted by priority)
registry.hooks_for(:pre_tool_use)  # => [#<callable>, ...]

# Clear hooks for one event or all events
registry.clear!(:pre_tool_use)
registry.clear!  # clears all

# List events with registered hooks
registry.registered_events  # => [:pre_tool_use, :post_llm_call, ...]
```

---

## Examples

### Block destructive shell commands

```yaml
# .rubyn-code/hooks.yml
pre_tool_use:
  - tool: bash
    match: "rm -rf /"
    action: deny
    reason: "System-wide recursive delete is not allowed"

  - tool: bash
    match: "DROP DATABASE"
    action: deny
    reason: "Database drops are blocked"

  - tool: bash
    match: "git push --force"
    action: deny
    reason: "Force push is prohibited"
```

### Protect specific directories

```yaml
pre_tool_use:
  - tool: write_file
    path: "vendor/**"
    action: deny
    reason: "Vendor directory is managed by Bundler"

  - tool: edit_file
    path: ".github/**"
    action: deny
    reason: "CI configuration requires manual review"

  - tool: write_file
    path: "db/migrate/**"
    action: deny
    reason: "Use rails generate migration instead"
```

### Audit all file writes

```yaml
post_tool_use:
  - tool: write_file
    action: log

  - tool: edit_file
    action: log
```

### Enforce Rails conventions

```yaml
pre_tool_use:
  - tool: bash
    match: "rake db:migrate"
    action: deny
    reason: "Use the db_migrate tool instead of running rake directly"

  - tool: bash
    match: "rails generate"
    action: deny
    reason: "Use the rails_generate tool for proper output handling"
```

### Log all tool usage

```yaml
post_tool_use:
  - action: log
```

This matches all tools (no `tool` filter) and writes every tool result to the
audit log.
