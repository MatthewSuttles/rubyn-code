# Refactoring: Separate Query from Modifier (CQS)

## Pattern

A method should either return a value (query) or change state (command), but not both. When a method does both — returns data AND has side effects — split it into two methods. This is the Command-Query Separation (CQS) principle.

```ruby
# BEFORE: Method both modifies state AND returns a value
class ShoppingCart
  def add_item(product, quantity: 1)
    item = @items.find { |i| i.product == product }
    if item
      item.quantity += quantity
    else
      @items << CartItem.new(product: product, quantity: quantity)
    end
    calculate_total  # Returns the new total — side effect + return value mixed
  end

  def remove_expired_items
    expired = @items.select { |item| item.product.expired? }
    @items -= expired
    expired  # Returns removed items AND modifies the cart
  end
end

# Usage is confusing — does this return something? Change something? Both?
total = cart.add_item(widget)
removed = cart.remove_expired_items
```

```ruby
# AFTER: Commands modify state. Queries return data. They don't overlap.
class ShoppingCart
  # COMMANDS: modify state, return nothing meaningful (or self for chaining)
  def add_item(product, quantity: 1)
    item = @items.find { |i| i.product == product }
    if item
      item.quantity += quantity
    else
      @items << CartItem.new(product: product, quantity: quantity)
    end
    nil  # Or `self` for chaining
  end

  def remove_expired_items
    @items.reject! { |item| item.product.expired? }
    nil
  end

  # QUERIES: return data, never modify state
  def total
    @items.sum { |item| item.quantity * item.product.price }
  end

  def expired_items
    @items.select { |item| item.product.expired? }
  end

  def item_count
    @items.sum(&:quantity)
  end

  def empty?
    @items.empty?
  end
end

# Usage is clear — commands do, queries ask
cart.add_item(widget, quantity: 2)
cart.remove_expired_items
puts cart.total
puts cart.expired_items.map(&:product_name)
```

### CQS in Rails

```ruby
# BEFORE: Scope that modifies data (violates CQS)
class Order < ApplicationRecord
  scope :archive_old, -> {
    where(created_at: ...90.days.ago).update_all(archived: true)
    # This is a command disguised as a scope — scopes should be queries
  }
end

# AFTER: Scope queries, service commands
class Order < ApplicationRecord
  scope :archivable, -> { where(created_at: ...90.days.ago, archived: false) }
end

class Orders::ArchiveService
  def self.call
    count = Order.archivable.update_all(archived: true, archived_at: Time.current)
    Result.new(success: true, count: count)
  end
end

# Usage
puts "#{Order.archivable.count} orders to archive"  # Query
Orders::ArchiveService.call                           # Command
```

```ruby
# BEFORE: Method that checks permission AND logs the attempt
class Authorization
  def authorized?(user, action)
    allowed = user.permissions.include?(action)
    AuditLog.create!(user: user, action: action, allowed: allowed)  # Side effect!
    allowed
  end
end

# Calling code doesn't expect a query to write to the database
if auth.authorized?(user, :delete_order)  # Surprise! This created an audit record
  order.destroy!
end

# AFTER: Separated
class Authorization
  def authorized?(user, action)
    user.permissions.include?(action)
  end

  def check_and_log(user, action)
    allowed = authorized?(user, action)
    AuditLog.create!(user: user, action: action, allowed: allowed)
    allowed
  end
end
```

## Why This Is Good

- **Queries are safe to call anywhere.** If `total` only reads data, calling it in a view, a test, or a debug session never changes state. No surprises.
- **Commands are explicit about mutation.** When you see `cart.add_item(widget)`, you know state is changing. When you see `cart.total`, you know it's read-only.
- **Easier to test.** Queries are tested with simple assertions on return values. Commands are tested by checking state before and after. When they're mixed, you have to assert both.
- **Easier to reason about.** In concurrent systems, queries are safe to parallelize. Commands need synchronization. Knowing which is which matters.
- **Caching is safe for queries.** You can cache `cart.total` because calling it doesn't change anything. If `total` also triggered a recalculation and saved to the database, caching it would be dangerous.

## When To Apply

- **Methods that both return a value AND modify state.** These are CQS violations. Split them.
- **ActiveRecord scopes that modify data.** Scopes should query. Services should command.
- **Methods named like queries that have side effects.** `user.authorized?` shouldn't write to an audit log. `user.full_name` shouldn't trigger a name parsing service.
- **APIs where calling a "getter" triggers unexpected behavior.** If reading a property sends an HTTP request, logs to a database, or increments a counter — separate the read from the write.

## When NOT To Apply

- **`save` and `update` return a boolean.** Rails' `order.save` both modifies state and returns true/false. This is a pragmatic CQS violation that Rails developers expect. Don't fight it.
- **`pop` and `shift` on arrays.** These both modify the array and return the removed element. They're standard Ruby and universally understood.
- **Idempotent cache operations.** `Rails.cache.fetch(key) { compute }` both reads and writes, but it's idempotent and universally expected. Don't split it.
- **The split would make code significantly harder to use.** CQS is a guideline for clarity. If separating a method makes the API confusing, keep them together and document the behavior.

## Edge Cases

**`find_or_create_by` is a deliberate CQS violation:**
```ruby
user = User.find_or_create_by(email: "alice@example.com") do |u|
  u.name = "Alice"
end
```
This queries and potentially creates. It's a Rails convention that everyone understands. Don't wrap it in a service object for CQS purity.

**The "Tell, Don't Ask" tension:**
CQS says "separate queries from commands." Tell Don't Ask says "don't query an object then act on the result — tell the object to act." These can conflict. In practice, CQS applies to individual methods, and Tell Don't Ask applies to object interactions. Both are guidelines, not laws.
