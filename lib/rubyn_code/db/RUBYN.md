# DB Layer

SQLite connection management and schema migrations.

## Classes

- **`Connection`** — Singleton SQLite3 connection to `~/.rubyn-code/rubyn_code.db`.
  Creates the directory and database on first access. Configures WAL mode and foreign keys.

- **`Migrator`** — Runs numbered `.sql` files from `db/migrations/`. Tracks applied migrations
  in `schema_migrations` table. Migrations are idempotent and run in order.

- **`Schema`** — Schema introspection utilities. Checks table existence, column info.
  Used by other layers to verify database state.
