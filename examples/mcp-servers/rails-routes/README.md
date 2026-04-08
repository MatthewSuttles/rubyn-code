# Rails Routes MCP Server

A Model Context Protocol (MCP) server that exposes Rails route information. Lets the AI assistant look up routes, find which controller handles a path, and filter routes by controller.

## Requirements

- Ruby 3.3+
- No external gems needed
- For best results, run from within a Rails project directory (or set `RAILS_ROOT`)

## Tools

### `list_routes`

Lists all routes in the Rails application. Returns the HTTP method, URL path pattern, and controller#action for each route.

### `routes_for_controller`

Filters routes by controller name.

**Parameters:**
- `controller` (string, required) — Controller name to filter by (e.g. "users", "api/v1/posts")

### `find_route`

Finds which controller#action handles a given URL path. Supports dynamic segments (e.g. `/users/123` matches `/users/:id`).

**Parameters:**
- `path` (string, required) — URL path to look up (e.g. "/users/123", "/api/v1/posts")

## How Routes Are Loaded

1. **Primary:** Runs `rails routes` as a subprocess and parses the output.
2. **Fallback:** If `rails routes` is not available (e.g. not in a Rails project, or Rails is not installed), reads `config/routes.rb` and extracts routes from the DSL. The DSL parser handles `get`, `post`, `put`, `patch`, `delete`, `resources`, and `root` declarations.

## Usage

### Standalone

```bash
# From within a Rails project directory
ruby server.rb

# Specify a Rails project path
RAILS_ROOT=/path/to/my/app ruby server.rb
```

### With rubyn-code

Add to your project's `.rubyn-code/mcp.json`:

```json
{
  "mcpServers": {
    "rails-routes": {
      "command": "ruby",
      "args": ["examples/mcp-servers/rails-routes/server.rb"],
      "env": {
        "RAILS_ROOT": "${PWD}"
      }
    }
  }
}
```

### Manual Testing

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ruby server.rb
```
