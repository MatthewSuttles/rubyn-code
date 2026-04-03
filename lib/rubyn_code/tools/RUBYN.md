# Layer 2: Tools

32 built-in tools that Claude can invoke. The extensibility surface of the system.

## Core Classes

- **`Base`** — Abstract base class. Subclasses define `self.tool_name`, `self.description`,
  `self.schema` (JSON Schema), and `execute(params)`. Returns a string result.

- **`Registry`** — Maps tool names to classes. Tools self-register on load.
  `Registry.find('read_file')` returns the tool class.

- **`Schema`** — Converts tool classes into Claude's expected tool definition format
  (name, description, input_schema).

- **`Executor`** — Dispatches tool calls. Checks `Permissions::Policy` before execution,
  wraps errors, and returns results. The bridge between Claude's tool_use blocks and Ruby.

## Tool Categories

| Category | Tools |
|----------|-------|
| File I/O | `read_file`, `write_file`, `edit_file`, `glob`, `grep` |
| Shell | `bash`, `background_run` |
| Rails | `rails_generate`, `db_migrate`, `run_specs`, `bundle_install`, `bundle_add` |
| Git | `git_commit`, `git_diff`, `git_log`, `git_status` |
| Web | `web_search`, `web_fetch` |
| Memory | `memory_search`, `memory_write` |
| Agents | `spawn_agent`, `spawn_teammate`, `send_message`, `read_inbox` |
| Meta | `compact`, `load_skill`, `task`, `review_pr` |

## Adding a Tool

1. Create `my_tool.rb` in this directory, inherit `Tools::Base`
2. Define `self.tool_name`, `self.description`, `self.schema`
3. Implement `execute(params)` — return a string
4. Add `autoload :MyTool` in `lib/rubyn_code.rb`
5. Register in `Tools::Registry`
