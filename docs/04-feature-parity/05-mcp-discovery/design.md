# 05 `.mcp.json` Auto-Discovery — Design

## Overview

Discover MCP server definitions from the project's `.mcp.json` at the
project root, merging them with the user-level config that
`MCP::Config.load` already returns. Each entry is tagged with its
source so `/mcp` can prefix them `[user]` vs `[project]`.

## Architecture

```
project root (/)
├── .mcp.json             # Claude Code layout — mcpServers: { name: { command|url, ... } }
└── .rubyn-code/mcp.json  # user-level layout (existing)

MCP::Discovery.discover(project_root)
  ├── user  = MCP::Config.load(project_root).entries → Entry(source: :user)
  ├── proj  = Discovery.load_project(project_root)
  └── user + proj
```

## Pieces

### `MCP::Discovery::Entry`

```ruby
Entry = Data.define(:name, :command, :args, :env, :url, :source)
```

### `MCP::Discovery.load_project(project_root)`

- `[]` for nil root / missing `.mcp.json`
- JSON.parse with three rescues (ParserError, SystemCallError, never raises)
- `build_entry` validates each entry (must have command OR url)
- `Array(data['mcpServers']).filter_map { build_entry(...) }`

### `MCP::Discovery.discover(project_root)`

- Concatenates user + project entries; user first so duplicate names
  resolve user-preferred

### Helper classifiers

```ruby
Discovery.stdio_servers(entries)   # .command non-empty
Discovery.remote_servers(entries)  # .command empty AND .url present
```

## Wiring (gap-closed in PRs #138, #139)

```ruby
# CLI::REPL#setup_mcp_servers!
entries = MCP::Discovery.discover(@project_root)
entries.each { |entry| connect_mcp_server(entry) }
```

```ruby
# CLI::Commands::Mcp#load_entries(project_root)
MCP::Discovery.discover(project_root)
```

The `/mcp` command prefixes each entry with `[project]` or `[user]`.

## Out-of-scope

- OAuth / auto-connection for URL-based servers (deferred per Gap 5 plan)
- `.mcp.json` from the global home directory (`~/.mcp.json`)
- Hot-reload during a REPL session (one-shot discovery on startup)
- Server lifecycle (start/stop/restart) — handled by existing `MCP::Client`