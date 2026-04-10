# RubyGems Lookup MCP Server

A Model Context Protocol (MCP) server that queries the RubyGems.org API. Lets the AI assistant search for gems, check versions, and inspect dependencies without leaving your coding session.

## Requirements

- Ruby 3.3+
- No external gems needed (uses `net/http` and `json` from stdlib)

## Tools

### `search_gems`

Searches RubyGems.org for gems matching a query. Returns the top 10 results with name, version, download count, and description.

**Parameters:**
- `query` (string, required) — Search query (gem name or keyword)

### `gem_info`

Returns detailed information about a specific gem including version, authors, description, homepage, source code URL, licenses, download count, and both runtime and development dependencies.

**Parameters:**
- `name` (string, required) — Exact gem name (e.g. "rails", "sidekiq")

### `gem_versions`

Lists the 20 most recent version releases for a gem, including version number, platform, release date, and download count.

**Parameters:**
- `name` (string, required) — Exact gem name

## Usage

### Standalone

```bash
ruby server.rb
```

### With rubyn-code

Add to your project's `.rubyn-code/mcp.json`:

```json
{
  "mcpServers": {
    "rubygems": {
      "command": "ruby",
      "args": ["examples/mcp-servers/rubygems-lookup/server.rb"]
    }
  }
}
```

### Manual Testing

```bash
# Initialize the server
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ruby server.rb

# Search for gems
echo '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_gems","arguments":{"query":"http client"}}}' | ruby server.rb
```

## API

This server queries the public RubyGems.org API at `https://rubygems.org/api/v1/`. No authentication is required. Please be mindful of rate limits when making many requests.
