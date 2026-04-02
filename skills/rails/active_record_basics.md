# Rails: ActiveRecord Best Practices

## Pattern

Use scopes for reusable query fragments, `find_by` over `where.first`, `exists?` over loading records to check presence, and `pluck` when you only need column values. Keep models focused on data access and validation, not business logic.

```ruby
class Order < ApplicationRecord
  # Scopes: named, chainable, readable
  scope :recent, -> { where(created_at: 30.days.ago..) }
  scope :pending, -> { where(status: :pending) }
  scope :shipped, -> { where(status: :shipped) }
  scope :for_user, ->(user) { where(user: user) }
  scope :high_value, -> { where("total >= ?", 200) }
  scope :by_newest, -> { order(created_at: :desc) }

  # Scopes compose naturally
  # Order.for_user(user).pending.recent.by_newest

  # Efficient existence checks
  def self.any_pending_for?(user)
    for_user(user).pending.exists?
  end

  # Efficient counting
  def self.total_revenue
    sum(:total)
  end

  # Efficient value extraction
  def self.recent_emails
    recent.joins(:user).pluck("users.email")
  end
end
```

```ruby
# CORRECT: Efficient queries
user = User.find_by(email: "alice@example.com")    # Returns nil if not found
user = User.find_by!(email: "alice@example.com")   # Raises RecordNotFound

order_exists = Order.where(user: user).exists?      # SELECT 1 ... LIMIT 1
order_count = user.orders.pending.count              # SELECT COUNT(*)
totals = Order.pending.pluck(:total)                 # SELECT total — returns array of values

# Batch processing for large datasets
Order.pending.find_each(batch_size: 500) do |order|
  Orders::ProcessService.call(order)
end

# Bulk operations without instantiating records
Order.where(status: :draft, created_at: ..30.days.ago).delete_all
Order.pending.update_all(status: :cancelled, cancelled_at: Time.current)

# insert_all for bulk creation (Rails 6+)
Order.insert_all([
  { user_id: 1, total: 100, status: :pending, created_at: Time.current, updated_at: Time.current },
  { user_id: 2, total: 200, status: :pending, created_at: Time.current, updated_at: Time.current }
])
```

## Why This Is Good

- **Scopes are chainable and composable.** `Order.pending.recent.high_value` reads like a sentence and generates a single SQL query. Each scope is a reusable building block.
- **`exists?` runs `SELECT 1 LIMIT 1`.** It doesn't load records into memory. Checking if a user has pending orders costs one lightweight query regardless of how many orders exist.
- **`pluck` skips model instantiation.** `Order.pluck(:total)` returns `[100, 200, 300]` without creating Order objects. For 10,000 records, this is dramatically faster and uses a fraction of the memory.
- **`find_each` prevents memory bloat.** Loading 100,000 orders with `.all.each` allocates all of them simultaneously. `find_each` loads 1,000 at a time (configurable) and GCs between batches.
- **`update_all` and `delete_all` execute single SQL statements.** No callbacks, no instantiation, no N individual UPDATE queries. For bulk operations on thousands of records, this is orders of magnitude faster.

## Anti-Pattern

Loading full records when you only need a check, a count, or a column value:

```ruby
# BAD: Loads ALL orders into memory to check if any exist
if user.orders.where(status: :pending).to_a.any?
  # ...
end

# BAD: Loads ALL records to count them
total = Order.where(status: :pending).to_a.length

# BAD: Loads full AR objects to get one column
emails = User.where(active: true).map(&:email)

# BAD: where().first instead of find_by
user = User.where(email: "alice@example.com").first

# BAD: Processing large datasets without batching
Order.all.each do |order|
  order.recalculate_total!
end

# BAD: N individual updates
Order.pending.each do |order|
  order.update(status: :cancelled)
end

# BAD: default_scope — almost always a mistake
class Order < ApplicationRecord
  default_scope { where(deleted: false) }
end
```

## Why This Is Bad

- **`.to_a.any?` loads every matching record.** 5,000 pending orders? That's 5,000 ActiveRecord objects instantiated, then thrown away after checking `any?`. `exists?` does the same check with zero objects loaded.
- **`.to_a.length` vs `.count`.** Loading 10,000 records to count them uses ~100MB of memory. `COUNT(*)` uses zero Ruby memory and returns instantly.
- **`.map(&:email)` instantiates every User.** For 50,000 users, that's 50,000 ActiveRecord objects in memory. `pluck(:email)` returns a simple array of strings with no model instantiation.
- **`.where().first` generates `ORDER BY id LIMIT 1`.** `find_by` generates `LIMIT 1` without the sort. On large tables without an index on the filter column, the sort is expensive.
- **Iterating without batching** loads the entire result set into memory at once. For large tables this can exhaust available RAM.
- **N individual updates** execute N separate UPDATE statements. Updating 1,000 orders takes 1,000 round trips to the database. `update_all` does it in one.
- **`default_scope` poisons every query.** Every `Order.find`, `Order.count`, `Order.joins` silently includes `WHERE deleted = false`. Forgetting to `unscope` it causes subtle bugs. Soft deletes should use explicit scopes or gems like `discard`.

## When To Apply

- **Every ActiveRecord query should be as efficient as possible.** Use the cheapest operation that satisfies the need: `exists?` > `count` > `pluck` > `select` > loading full records.
- **Scopes for any query used in more than one place.** If two controllers filter by pending status, define `scope :pending`.
- **`find_each` for any iteration over more than 100 records.**
- **`update_all`/`delete_all` for bulk operations** where you don't need callbacks or validations.

## When NOT To Apply

- **Small datasets where clarity wins.** If you have 10 records and `.map(&:name)` is more readable than `.pluck(:name)` in context, the performance difference is negligible.
- **When you need callbacks to fire.** `update_all` skips callbacks and validations. If the model's `after_update` callback must run, iterate and save individually (but consider whether the callback should be a service object instead).
- **Don't over-scope.** A scope used in exactly one place adds indirection without reuse benefit. An inline `where` is fine for one-off queries.

## Edge Cases

**Scopes vs class methods:**
Scopes always return a relation (even when the condition is nil). Class methods can return nil, breaking chains.

```ruby
# Scope: always chainable even when condition is nil
scope :by_status, ->(status) { where(status: status) if status.present? }

# Class method: can break the chain if it returns nil
def self.by_status(status)
  return none unless status.present?  # Must return a relation, not nil
  where(status: status)
end
```

**`select` vs `pluck`:**
`select` returns ActiveRecord objects with limited attributes. `pluck` returns raw arrays. Use `select` when you need methods on the model. Use `pluck` when you just need values.

```ruby
Order.select(:id, :total).each { |o| o.total }  # AR objects, can call methods
Order.pluck(:id, :total)                          # [[1, 100], [2, 200]] — raw arrays
```

**Counter caches for frequently counted associations:**

```ruby
# Migration
add_column :users, :orders_count, :integer, default: 0

# Model
class Order < ApplicationRecord
  belongs_to :user, counter_cache: true
end

# Now user.orders_count is a column read, not a COUNT(*) query
```

**`find_or_create_by` race conditions:**
Use `create_or_find_by` (Rails 6+) with a unique database constraint to handle concurrency:

```ruby
# Safe under concurrency with a unique index on email
user = User.create_or_find_by(email: "alice@example.com") do |u|
  u.name = "Alice"
end
```
