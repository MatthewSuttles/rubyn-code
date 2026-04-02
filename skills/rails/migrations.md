# Rails: Safe Migrations

## Pattern

Write migrations that are safe for zero-downtime deploys. Add indexes concurrently. Never remove columns without a two-step deploy. Use `strong_migrations` gem to catch unsafe operations automatically.

```ruby
# SAFE: Add a column with a default (Rails 5+ handles this without rewriting the table)
class AddStatusToOrders < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :priority, :integer, default: 0, null: false
  end
end
```

```ruby
# SAFE: Add an index concurrently (doesn't lock the table)
class AddIndexOnOrdersStatus < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :orders, :status, algorithm: :concurrently
  end
end
```

```ruby
# SAFE: Two-step column removal
# Deploy 1: Stop using the column in code, add ignore
class IgnoreDeletedAtOnOrders < ActiveRecord::Migration[8.0]
  def change
    safety_assured { remove_column :orders, :deleted_at, :datetime }
  end
end
# But first: update the model to ignore the column
# class Order < ApplicationRecord
#   self.ignored_columns += ["deleted_at"]
# end
```

```ruby
# SAFE: Rename via add/copy/remove (not rename_column)
# Step 1: Add new column
class AddFullNameToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :full_name, :string
  end
end

# Step 2: Backfill data (in a separate migration or rake task)
class BackfillFullName < ActiveRecord::Migration[8.0]
  def up
    User.in_batches.update_all("full_name = name")
  end

  def down
    # no-op
  end
end

# Step 3: (After deploy) Remove old column
class RemoveNameFromUsers < ActiveRecord::Migration[8.0]
  def change
    safety_assured { remove_column :users, :name, :string }
  end
end
```

```ruby
# SAFE: Add a foreign key constraint
class AddForeignKeyOnOrders < ActiveRecord::Migration[8.0]
  def change
    add_foreign_key :orders, :users, validate: false
  end
end

# Separate migration to validate (non-blocking)
class ValidateForeignKeyOnOrders < ActiveRecord::Migration[8.0]
  def change
    validate_foreign_key :orders, :users
  end
end
```

Add `strong_migrations` to catch unsafe operations:

```ruby
# Gemfile
gem 'strong_migrations'

# config/initializers/strong_migrations.rb
StrongMigrations.start_after = 20260101000000
```

## Why This Is Good

- **Zero-downtime deploys.** The new code deploys while the migration runs. No maintenance window, no "please wait" page, no interruption to users.
- **Concurrent indexes don't lock.** `algorithm: :concurrently` builds the index without locking the table for writes. A standard `add_index` on a 10-million-row table locks writes for minutes.
- **Two-step column removal prevents errors.** If you remove a column while old code is still running (during deploy), queries referencing that column fail. Ignoring the column first ensures old code doesn't reference it.
- **`strong_migrations` catches mistakes.** It raises an error if you try to run an unsafe migration in production, with a helpful message explaining the safe alternative.
- **Separate validation of foreign keys.** Adding a FK with `validate: false` is instant. Validating it in a separate migration scans the table without blocking writes.

## Anti-Pattern

Migrations that lock tables, remove columns in one step, or change types without safety:

```ruby
# DANGEROUS: Locks the entire table while building the index
class AddIndexOnOrdersEmail < ActiveRecord::Migration[8.0]
  def change
    add_index :orders, :email  # Blocks writes on large tables
  end
end
```

```ruby
# DANGEROUS: Removes column while running code may still reference it
class RemoveLegacyField < ActiveRecord::Migration[8.0]
  def change
    remove_column :orders, :old_status  # Active servers still querying old_status
  end
end
```

```ruby
# DANGEROUS: Changes column type — rewrites entire table, locks it
class ChangeOrderTotalType < ActiveRecord::Migration[8.0]
  def change
    change_column :orders, :total, :decimal, precision: 10, scale: 2
  end
end
```

```ruby
# DANGEROUS: Data migration mixed with schema migration
class AddAndBackfillStatus < ActiveRecord::Migration[8.0]
  def change
    add_column :orders, :status, :string, default: "pending"
    Order.update_all(status: "pending")  # Locks table, runs in same transaction
  end
end
```

## Why This Is Bad

- **Table locks block writes.** A standard `add_index` acquires an exclusive lock on the table. On a 10-million-row orders table, this blocks all INSERT/UPDATE/DELETE for 5-30 minutes. Every request that touches orders hangs.
- **Column removal during deploy breaks requests.** Rails caches the column list at boot. Old servers (still running during rolling deploy) try to SELECT the removed column and get a database error.
- **Type changes rewrite the entire table.** Changing a column type on a 50-million-row table creates a new copy of the table with the new type, copies all data, then swaps. This locks the table for the entire duration.
- **Data migrations in schema migrations are dangerous.** They run inside the migration transaction, hold locks longer, and can timeout. If they fail halfway, the schema migration rolls back too. Keep data migrations separate.

## When To Apply

- **Every migration in a production application.** Even if you're small now, building safe habits means you never have to relearn when your tables grow to millions of rows.
- **`add_index` on any table with more than 10,000 rows** should use `algorithm: :concurrently`.
- **Any column removal** should use the two-step process: ignore first, remove in a later deploy.
- **Any column type change** should use the add-new/copy/remove-old pattern.
- **Data backfills** should be separate from schema changes, use `in_batches`, and run outside the migration transaction.

## When NOT To Apply

- **Brand new tables** (no data yet) can have indexes added normally. No need for `concurrently` on an empty table.
- **Development/test environments** don't need concurrent indexes or two-step removal. These safeguards are for production deploys.
- **Tiny tables** (reference data with 100 rows) can be modified with standard migrations. The lock duration is negligible.

## Edge Cases

**Adding a NOT NULL column to an existing table:**
Add the column as nullable first, backfill, then add the constraint:

```ruby
# Step 1
add_column :orders, :region, :string

# Step 2 (separate migration)
Order.in_batches.update_all(region: "us")

# Step 3 (separate migration)
change_column_null :orders, :region, false
```

**Adding a column with a default on PostgreSQL:**
Rails 5+ with PostgreSQL adds the default at the column metadata level, not by rewriting the table. This is safe and instant. But always verify your Rails and PostgreSQL versions support this.

**`reversible` for complex migrations:**

```ruby
class AddStatusIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    reversible do |dir|
      dir.up { add_index :orders, :status, algorithm: :concurrently }
      dir.down { remove_index :orders, :status }
    end
  end
end
```

**Renaming tables:**
Don't. Add a new table, migrate data, drop the old one. Or use a database view as an alias during the transition.
