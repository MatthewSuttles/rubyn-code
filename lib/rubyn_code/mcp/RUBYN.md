# Layer 15: MCP (Model Context Protocol)

Client for connecting to external MCP tool servers.

## Classes

- **`Client`** — JSON-RPC 2.0 client that discovers and invokes tools on MCP servers.
  Handles initialization, tool listing, and tool execution.

- **`StdioTransport`** — Subprocess transport via `Open3.popen3`. Communicates over
  stdin/stdout with newline-delimited JSON-RPC. Default timeout: 30s.

- **`SSETransport`** — HTTP Server-Sent Events transport. Long-lived GET for events,
  POST for JSON-RPC requests. Default timeout: 30s.

- **`ToolBridge`** — Dynamically creates `Tools::Base` subclasses from MCP tool definitions.
  Prefixes tool names with `mcp_`, sets risk level to `:external`, and registers them
  in `Tools::Registry`. Delegates `execute` to the MCP client.

- **`Config`** — Loads MCP server configuration from `.rubyn-code/mcp.json`.
  Supports environment variable interpolation in config values via `${VAR}` syntax.
