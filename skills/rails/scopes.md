# Rails: ActiveRecord Scopes

## Pattern

Scopes are named, reusable query fragments that return `ActiveRecord::Relation`. They chain, compose, and serve as the vocabulary for querying your domain. Design scopes like building blocks — small, focused, and combinable.

```ruby
class Order < ApplicationRecord
  # Status scopes — named after the state
  scope :pending, -> { where(status: :pending) }
  scope :confirmed, -> { where(status: :confirmed) }
  scope :shipped, -> { where(status: :shipped) }
  scope :completed, -> { where(status: %i[shipped delivered]) }
  scope :active, -> { where.not(status: :cancelled) }

  # Time scopes — named after the time frame
  scope :recent, -> { where(created_at: 30.days.ago..) }
  scope :today, -> { where(created_at: Date.current.all_day) }
  scope :this_month, -> { where(created_at: Date.current.all_month) }
  scope :before, ->(date) { where(created_at: ...date) }
  scope :after, ->(date) { where(created_at: date..) }
  scope :between, ->(start_date, end_date) { where(created_at: start_date..end_date) }

  # Relationship scopes — named after the association
  scope :for_user, ->(user) { where(user: user) }
  scope :for_product, ->(product) { joins(:line_items).where(line_items: { product: product }) }

  # Value scopes — named after what they filter
  scope :high_value, -> { where("total >= ?", 200_00) }
  scope :above, ->(amount) { where("total >= ?", amount) }
  scope :free_shipping, -> { where("total >= ?", 50_00) }

  # Ordering scopes
  scope :by_newest, -> { order(created_at: :desc) }
  scope :by_total, -> { order(total: :desc) }
  scope :by_status, -> { order(:status) }

  # Inclusion scopes — preload associations for performance
  scope :with_details, -> { includes(:user, :line_items, line_items: :product) }
  scope :with_user, -> { includes(:user) }
end

# Compose scopes naturally — reads like a sentence
Order.for_user(current_user).pending.recent.by_newest
Order.confirmed.high_value.with_details.by_total
Order.active.this_month.for_product(widget)
```

### Scopes with Conditional Logic

```ruby
class Product < ApplicationRecord
  # Parameterized scope — nil-safe
  scope :in_category, ->(category) { where(category: category) if category.present? }
  scope :cheaper_than, ->(price) { where("price <= ?", price) if price.present? }
  scope :search, ->(query) {
    where("name ILIKE :q OR sku ILIKE :q", q: "%#{sanitize_sql_like(query)}%") if query.present?
  }

  # Scope that wraps a subquery
  scope :with_recent_orders, -> {
    where(id: LineItem.joins(:order).where(orders: { created_at: 30.days.ago.. }).select(:product_id))
  }

  # Scope using merge to combine conditions from another model's scope
  scope :ordered_recently, -> {
    joins(:line_items).merge(LineItem.joins(:order).merge(Order.recent)).distinct
  }
end

# Nil-safe scopes chain gracefully — nil params are ignored
Product.in_category(params[:category]).cheaper_than(params[:max_price]).search(params[:q])
# If params[:category] is nil, that scope returns `all` — the chain continues
```

### Scopes vs Class Methods

```ruby
class Order < ApplicationRecord
  # SCOPE: Always returns a relation, even when the condition is nil
  scope :by_status, ->(status) { where(status: status) if status.present? }
  # When status is nil: returns `all` (chainable)

  # CLASS METHOD: Can return nil, breaking the chain
  def self.by_status(status)
    return if status.blank?  # Returns nil — .by_newest chained after this explodes
    where(status: status)
  end

  # FIX: Class method that always returns a relation
  def self.by_status(status)
    return all if status.blank?  # Returns scope, not nil
    where(status: status)
  end
end
```

**Rule:** Use scopes for simple query fragments. Use class methods when you need complex logic (multiple lines, early returns, error handling) — but always return a relation or `all`/`none`, never `nil`.

## Why This Is Good

- **Composable.** Each scope is a LEGO brick. Snap them together in any combination. `Order.pending.recent.high_value` generates one SQL query with three WHERE clauses.
- **Readable.** `Order.for_user(user).completed.this_month` reads like English. The equivalent raw SQL is harder to scan and impossible to reuse.
- **Chainable.** Scopes return `ActiveRecord::Relation`, so you can always chain more scopes, `.count`, `.page()`, `.pluck()`, `.exists?` after them.
- **Nil-safe.** A scope with `if condition.present?` returns `all` when the condition is false — the chain continues without breaking. This makes conditional filtering trivial.
- **Single source of truth.** "What does 'recent' mean?" is answered in one place — the scope definition. Not scattered across 8 controllers with slightly different `where` clauses.
- **Preloadable.** Scopes work with `includes`, `preload`, and `eager_load`. Query objects that return arrays don't.

## Anti-Pattern

```ruby
class Order < ApplicationRecord
  # BAD: default_scope — poisons every query
  default_scope { where(deleted: false) }
  # Every Order.find, Order.count, Order.joins silently adds WHERE deleted = false
  # Forgetting to unscope causes subtle bugs

  # BAD: Scope that returns an array, not a relation
  scope :totals, -> { pluck(:total) }
  # Can't chain: Order.totals.pending → NoMethodError

  # BAD: Scope with side effects
  scope :expire_old, -> {
    where(created_at: ...30.days.ago).update_all(status: :expired)
  }
  # Scopes should query, not mutate. This belongs in a service object.

  # BAD: Overly complex scope that should be a query object
  scope :dashboard_summary, -> {
    select("status, COUNT(*) as count, SUM(total) as revenue")
      .where(created_at: 30.days.ago..)
      .where.not(status: :cancelled)
      .group(:status)
      .having("COUNT(*) > ?", 0)
      .order("revenue DESC")
  }
end
```

## When To Apply

- **Every reusable query condition** that's used in 2+ places. If two controllers filter by `pending`, that's a scope.
- **Parameterized filters.** `scope :for_user, ->(user)` is cleaner than `where(user: user)` repeated everywhere.
- **Ordering.** `scope :by_newest` is more expressive than `.order(created_at: :desc)` in every controller.
- **Eager loading bundles.** `scope :with_details` bundles the `includes` for a specific use case.

## When NOT To Apply

- **Complex queries with 4+ joins, subqueries, or CTEs.** These belong in a Query Object, not a scope.
- **Queries with side effects.** Scopes should never `update_all`, send emails, or modify state. They read data.
- **One-off queries.** If a query is only used in one place and is simple (one `where` clause), inline it. Don't create a scope for everything.
- **Never use `default_scope`.** It silently affects every query on the model. Use explicit scopes and apply them where needed.

## Edge Cases

**Merging scopes across models:**

```ruby
# merge applies another model's scope in a join
Order.joins(:user).merge(User.active)
# WHERE users.active = true

# Useful for combining scopes from both sides of a join
Order.confirmed.joins(:user).merge(User.active).merge(User.pro_plan)
```

**Scopes on associations:**

```ruby
class User < ApplicationRecord
  has_many :orders
  has_many :pending_orders, -> { pending }, class_name: "Order"
  has_many :recent_orders, -> { recent.by_newest }, class_name: "Order"
end

user.pending_orders  # Preloadable scoped association
User.includes(:pending_orders)  # Works with includes
```

**`none` scope for empty results:**

```ruby
def orders_for(user)
  return Order.none unless user&.active?  # Returns empty relation, still chainable
  user.orders.active
end
```
