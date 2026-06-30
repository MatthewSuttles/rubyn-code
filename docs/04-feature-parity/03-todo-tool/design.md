# 03 TodoWrite Live Checklist — Design

## Overview

A `TodoWrite` tool that the model uses mid-turn to publish a structured
checklist of what it is doing right now. The renderer reprints the
checklist above the spinner on every tool result so the user sees
progress at a glance.

## Architecture

```
Model emits  tool_use { name: "TodoWrite", input: { todos: [...] } }
  │
  ▼
Tools::Executor#execute("TodoWrite")
  ├── build_tool("TodoWrite")   # → Tools::TodoWrite sharing @todo_store
  └── tool.execute(todos: ...)  # mutates @store, returns formatted string
        │
        ▼
  on_tool_result("TodoWrite", output)
        │
        ▼
  CLI::REPL#handle_on_tool_result
        ├── @renderer.tool_result(name, result)
        ├── render_todo_checklist                ← NEW
        └── @spinner.start
```

## Pieces

### `Tools::TodoStore`

```ruby
class TodoStore
  Item = Data.define(:content, :status, :active_form)
  def replace(items)
  def current
  def clear
  def empty?
  def render          # "☑ a\n[~] b\n[ ] c"
end
```

`MonitorMixin` provides thread-safe replace.

### `Tools::TodoWrite`

```ruby
PARAMETERS = {
  todos: { type: :array, required: true, ... }
}.freeze

RISK_LEVEL = :read
REQUIRES_CONFIRMATION = false
```

### `Tools::Executor#build_tool`

Detects tools whose `initialize` accepts `store:` and injects the
loop's store via `instance_variable_set(:@store, todo_store)` —
analogous to the existing `ide_client` injection.

### `Agent::Loop`

- Owns the `Tools::TodoStore` (opts default `Tools::TodoStore.new`)
- Wires `@tool_executor.todo_store = @todo_store`
- Clears the store on `initialize_session!` per turn
- `attr_reader :todo_store` for the renderer

### CLI rendering

```ruby
def render_todo_checklist
  return unless @agent_loop.respond_to?(:todo_store)
  store = @agent_loop.todo_store
  return if store.nil? || store.empty?
  @renderer.info("☐ Checklist:\n#{store.render}")
end
```

## Out of scope

- Cross-tool persistence (clears on session init)
- Synced client-side UI for IDE
- Per-task subtasks
