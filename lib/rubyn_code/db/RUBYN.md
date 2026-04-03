# DB Layer

SQLite connection management and schema migrations.

## Classes

- **`Connection`** — Singleton SQLite3 connection to `~/.rubyn-code/rubyn_code.db`.
  Creates the directory and database on first access. Configures WAL mode and foreign keys.

- **`Migrator`** — Runs numbered migration files from `db/migrations/`. Tracks applied migrations
  in `schema_migrations` table. Migrations are idempotent and run in order.
  Supports two formats:
  - `.sql` — executed statement-by-statement inside a transaction
  - `.rb` — Ruby module with `module_function def up(db)` for conditional/complex migrations
    (e.g. detecting column names via `pragma_table_info` before altering)

- **`Schema`** — Schema introspection utilities. Checks table existence, column info.
  Used by other layers to verify database state.

## Writing a Ruby Migration

Use `.rb` when you need branching logic that pure SQL can't handle (e.g. schema detection):

```ruby
# db/migrations/011_fix_something.rb
module Migration011FixSomething
  module_function

  def up(db)
    columns = db.query("SELECT name FROM pragma_table_info('my_table')").to_a
    column_names = columns.map { |c| c['name'] }

    if column_names.include?('old_column')
      db.execute("ALTER TABLE my_table RENAME COLUMN old_column TO new_column")
    end
  end
end
```

Module name is derived from filename: `011_fix_something.rb` → `Migration011FixSomething`.
