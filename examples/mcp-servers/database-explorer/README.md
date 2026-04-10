# Database Explorer MCP Server

A Model Context Protocol (MCP) server that provides read-only access to SQLite databases. Useful for letting the AI assistant inspect your Rails development database schema and data.

## Requirements

- Ruby 3.3+
- `sqlite3` gem (`gem install sqlite3`)

## Tools

### `list_tables`

Returns all table names in the database.

### `describe_table`

Returns column definitions (name, type, nullable, default, primary key) and indexes for a given table.

**Parameters:**
- `table_name` (string, required) — The name of the table to describe

### `query`

Executes a read-only SQL query. Only SELECT statements are allowed; write operations (INSERT, UPDATE, DELETE, DROP, etc.) are rejected.

**Parameters:**
- `sql` (string, required) — The SQL SELECT query to execute

## Usage

### Standalone

```bash
# Via environment variable
DATABASE_PATH=db/development.sqlite3 ruby server.rb

# Via command-line argument
ruby server.rb db/development.sqlite3
```

### With rubyn-code

Add to your project's `.rubyn-code/mcp.json`:

```json
{
  "mcpServers": {
    "database-explorer": {
      "command": "ruby",
      "args": ["examples/mcp-servers/database-explorer/server.rb"],
      "env": {
        "DATABASE_PATH": "db/development.sqlite3"
      }
    }
  }
}
```

### Manual Testing

```bash
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | DATABASE_PATH=db/dev.sqlite3 ruby server.rb
```

## Security Notes

- The database is opened in **read-only mode** — no writes are possible at the SQLite level.
- SQL queries are additionally checked to reject write statements.
- Table names are sanitized to prevent SQL injection in PRAGMA queries.
