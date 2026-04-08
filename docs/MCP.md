# MCP (Model Context Protocol)

MCP is an open protocol that lets AI assistants connect to external data sources
and tools through a standardised interface. Instead of building custom
integrations for every service, MCP servers expose capabilities via JSON-RPC 2.0
and any MCP-aware client --- including Rubyn Code --- can discover and invoke
them at runtime.

Rubyn Code's MCP subsystem lives in `lib/rubyn_code/mcp/` and is composed of
five modules:

| Module           | Responsibility |
|------------------|----------------|
| `Config`         | Reads `.rubyn-code/mcp.json` and expands `${ENV_VAR}` references |
| `Client`         | Manages the connect / discover / call / disconnect lifecycle |
| `StdioTransport` | Spawns a local subprocess and speaks JSON-RPC over stdin/stdout |
| `SSETransport`   | Connects to a remote server via HTTP Server-Sent Events |
| `ToolBridge`     | Wraps discovered MCP tools as native Rubyn Code tool classes |

---

## Configuration

Create a file called `.rubyn-code/mcp.json` in your project root. The format
mirrors the configuration used by other MCP-compatible clients:

```json
{
  "mcpServers": {
    "server-name": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "${GITHUB_TOKEN}"
      }
    }
  }
}
```

### Fields

| Field     | Type               | Required | Description |
|-----------|--------------------|----------|-------------|
| `command` | `String`           | Yes (stdio) | Executable to spawn (e.g. `npx`, `node`, `ruby`) |
| `args`    | `Array<String>`    | No       | Arguments passed to `command` |
| `env`     | `Hash<String,String>` | No    | Extra environment variables for the subprocess |
| `url`     | `String`           | Yes (SSE) | URL of a remote MCP server's SSE endpoint |
| `timeout` | `Integer`          | No       | Per-request timeout in seconds (default: 30) |

A server entry with a `url` key uses `SSETransport`; all others use
`StdioTransport`.

### Environment variable interpolation

Values in the `env` hash may reference shell environment variables with the
`${VAR_NAME}` syntax. At load time, `Config.expand_value` replaces each
reference with the value of `ENV[VAR_NAME]`. If the variable is not set, a
warning is printed and the reference is replaced with an empty string.

```json
{
  "env": {
    "DATABASE_URL": "${DATABASE_URL}",
    "API_KEY": "${MY_SERVICE_API_KEY}"
  }
}
```

### SSE transport example

```json
{
  "mcpServers": {
    "remote-tools": {
      "url": "https://mcp.example.com/sse",
      "timeout": 60
    }
  }
}
```

---

## How it works

The full lifecycle from configuration to tool availability:

1. **Config loaded** -- `MCP::Config.load(project_path)` reads
   `.rubyn-code/mcp.json` and returns an array of server config hashes.
   Environment variable references (`${VAR}`) are expanded at this stage.

2. **Client created** -- `MCP::Client.from_config(server_config)` inspects
   the config hash. If a `:url` key is present it creates an `SSETransport`;
   otherwise it creates a `StdioTransport`. A `Client` wraps the transport.

3. **Client connects** -- `client.connect!` starts the transport (spawning a
   subprocess for stdio, or opening an SSE stream for HTTP) and performs the
   MCP `initialize` handshake. The client sends its name, version, and
   capabilities, and receives the server's info and capabilities in return.
   After a successful handshake, a `notifications/initialized` notification
   is sent to the server.

4. **Tools discovered** -- `client.tools` sends a `tools/list` request.
   The server responds with an array of tool definitions, each containing a
   `name`, `description`, and `inputSchema` (JSON Schema).

5. **Tools bridged** -- `MCP::ToolBridge.bridge(client)` iterates the
   discovered tool definitions and dynamically creates a `Tools::Base`
   subclass for each one. The class is prefixed with `mcp_` (e.g. a remote
   tool named `query_db` becomes `mcp_query_db`), assigned `RISK_LEVEL =
   :external`, and registered with `Tools::Registry`.

6. **Available to agent** -- The agent loop's tool executor can now invoke
   the bridged tools like any built-in tool. When the LLM calls
   `mcp_query_db`, the bridged class delegates to `client.call_tool` which
   sends a `tools/call` JSON-RPC request to the server and returns the
   result.

7. **Disconnect** -- On shutdown, `client.disconnect!` stops the transport,
   terminating the subprocess or closing the SSE connection.

---

## Writing custom MCP servers

An MCP server is any process that speaks JSON-RPC 2.0 over one of the
supported transports (stdio or SSE). Below is the minimum protocol a server
must implement.

### `initialize` (handshake)

**Request** (from client):
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": { "tools": {} },
    "clientInfo": { "name": "rubyn-code", "version": "0.3.0" }
  }
}
```

**Response** (from server):
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "2024-11-05",
    "capabilities": { "tools": {} },
    "serverInfo": { "name": "my-server", "version": "1.0.0" }
  }
}
```

After receiving the response, the client sends a notification:
```json
{ "jsonrpc": "2.0", "method": "notifications/initialized" }
```

### `tools/list`

**Request**:
```json
{ "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {} }
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "result": {
    "tools": [
      {
        "name": "query_db",
        "description": "Run a read-only SQL query",
        "inputSchema": {
          "type": "object",
          "properties": {
            "sql": { "type": "string", "description": "SQL query to execute" }
          },
          "required": ["sql"]
        }
      }
    ]
  }
}
```

### `tools/call`

**Request**:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "tools/call",
  "params": {
    "name": "query_db",
    "arguments": { "sql": "SELECT COUNT(*) FROM users" }
  }
}
```

**Response**:
```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "content": [
      { "type": "text", "text": "count: 42" }
    ]
  }
}
```

Content blocks may have a `type` of `"text"`, `"image"` (with `mimeType` and
base64 `data`), or `"resource"` (with a nested `uri` and optional `text`).

### Error handling

If the server encounters an error, it must return a JSON-RPC error object:

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "error": {
    "code": -32600,
    "message": "Invalid query: syntax error near 'SELCT'"
  }
}
```

Standard JSON-RPC error codes apply (`-32700` parse error, `-32600` invalid
request, `-32601` method not found, `-32602` invalid params, `-32603`
internal error). Servers may also use application-specific codes.

---

## Example servers

The `examples/mcp-servers/` directory contains three reference
implementations:

| Server                | Description |
|-----------------------|-------------|
| `database-explorer`   | Exposes read-only SQL queries against a project database |
| `rubygems-lookup`     | Searches RubyGems.org for gem metadata and versions |
| `rails-routes`        | Lists Rails routes for the current project |

Each example includes a README with setup instructions and a sample
`mcp.json` snippet.

---

## Troubleshooting

### Server not found

```
Failed to start MCP server: No such file or directory - my-server
```

The `command` in your `mcp.json` must be on your `$PATH` (or an absolute
path). For Node-based servers, ensure `npx` is installed and the package name
is correct.

### Connection timeout

```
MCP server did not respond within 30s
```

The server did not complete the `initialize` handshake in time. Check that
the server starts quickly, prints JSON-RPC to stdout (stdio) or sends the
`endpoint` SSE event (SSE), and does not block on missing configuration.
You can increase the timeout via the `timeout` field in `mcp.json`.

### Environment variables not set

```
[MCP::Config] Environment variable GITHUB_TOKEN is not set
```

A `${VAR}` reference in your `env` config could not be resolved. Export the
variable in your shell before launching Rubyn Code, or add it to your
`.env` / shell profile.

### Transport already started

```
Transport already started
```

`connect!` was called on a client that is already connected. This usually
indicates a lifecycle bug. Call `disconnect!` before reconnecting.

### MCP error with code

```
MCP error (-32601): Method not found
```

The server does not implement the method the client requested. Ensure your
server handles `initialize`, `tools/list`, and `tools/call`.

### SSE endpoint not provided

```
MCP server did not provide an endpoint within 30s
```

For SSE servers, the initial GET request must receive an `event: endpoint`
SSE event containing the URL for POST requests. Make sure your server sends
this event immediately after the connection is established.
