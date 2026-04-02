# Rails: N+1 Query Prevention

## Pattern

Always preload associated records before iterating over a collection that accesses those associations. Use `includes` for most cases, `preload` when you need to force separate queries, and `eager_load` when you need to filter or sort by the association.

```ruby
# CORRECT: Preload associations before iteration
class OrdersController < ApplicationController
  def index
    @orders = current_user.orders
                          .includes(:line_items, :shipping_address, line_items: :product)
                          .order(created_at: :desc)
                          .page(params[:page])
  end
end
```

```erb
<%# This now executes 3-4 queries total, not 1 + N + N + N %>
<% @orders.each do |order| %>
  <p><%= order.shipping_address.city %></p>
  <% order.line_items.each do |item| %>
    <p><%= item.product.name %> x <%= item.quantity %></p>
  <% end %>
<% end %>
```

The three preloading methods and when to use each:

```ruby
# includes: Rails picks the strategy (usually 2 queries, switches to LEFT JOIN if you filter)
Order.includes(:line_items).where(line_items: { product_id: 5 })

# preload: Always separate queries. Use when includes tries a JOIN and you want separate queries.
Order.preload(:line_items).order(created_at: :desc)

# eager_load: Always LEFT OUTER JOIN. Use when you need to WHERE or ORDER BY the association.
Order.eager_load(:line_items).where("line_items.quantity > ?", 5)
```

Enable `strict_loading` on models or associations to catch N+1 queries during development:

```ruby
# On a model — raises if any lazy-loaded association is accessed
class Order < ApplicationRecord
  self.strict_loading_by_default = true # Rails 7+

  has_many :line_items
end

# On a specific query
orders = Order.strict_loading.all
orders.first.line_items # => raises ActiveRecord::StrictLoadingViolationError

# On a specific association
class Order < ApplicationRecord
  has_many :line_items, strict_loading: true
end
```

## Why This Is Good

- **Predictable query count.** With `includes`, a page listing 25 orders with line items and products executes 3-4 queries regardless of how many records exist. Without it, you execute 1 + 25 + 25 + 25 = 76 queries.
- **Scales linearly.** The query count depends on the number of associations, not the number of records. 25 orders or 2,500 orders — same number of queries.
- **`strict_loading` catches mistakes early.** Lazy-loaded associations silently work in development but crush production databases. Strict loading turns silent performance bugs into loud development errors.
- **No code change needed in views/serializers.** The fix is in the query, not in the template. The view code stays the same — it just runs faster.

## Anti-Pattern

Loading a collection and letting Rails lazy-load associations on each iteration:

```ruby
class OrdersController < ApplicationController
  def index
    @orders = current_user.orders.order(created_at: :desc).page(params[:page])
  end
end
```

```erb
<%# This triggers N+1 queries: 1 for orders, then 1 per order for each association %>
<% @orders.each do |order| %>
  <p><%= order.user.name %></p>           <%# N queries %>
  <p><%= order.shipping_address.city %></p> <%# N queries %>
  <% order.line_items.each do |item| %>     <%# N queries %>
    <p><%= item.product.name %></p>         <%# N * M queries %>
  <% end %>
<% end %>
```

## Why This Is Bad

- **Query count explodes.** 25 orders × 4 associations = 101 queries for one page load. With nested associations (line_items → product), it's even worse.
- **Invisible in development.** With 5 seed records, 21 queries feel instant. In production with 50 records per page, the same code makes 201 queries and takes 3 seconds.
- **Database connection saturation.** Each N+1 query is a round trip to the database. At scale, this saturates the connection pool and causes request queuing for other users.
- **Log noise.** Your development log fills with repetitive SELECT statements, burying actual issues.

## When To Apply

- **Every time you iterate over a collection and access an association.** This is not optional. Any `@records.each` that touches an association needs preloading.
- **In serializers and API responses.** JSON serialization that includes associated data triggers the same N+1 if not preloaded.
- **In background jobs.** Jobs that process batches of records with associations need preloading too — they just waste database time silently instead of slowing a web response.
- **In mailer views.** Mailers often render templates with associated data. Preload before passing records to the mailer.

## When NOT To Apply

- **Single record lookups.** `Order.find(params[:id])` followed by `@order.line_items` is two queries. That's fine — it's not N+1, it's 1+1.
- **When you only need IDs.** Use `@order.line_item_ids` which uses a single pluck query. No need to preload full records.
- **Counter caches.** If you only need `@order.line_items.count`, add a `counter_cache: true` to the association instead of preloading.

## Edge Cases

**You're not sure which associations the view will access:**
Use the `bullet` gem in development. It detects N+1 queries at runtime and tells you exactly which `includes` to add.

```ruby
# Gemfile
group :development do
  gem 'bullet'
end

# config/environments/development.rb
config.after_initialize do
  Bullet.enable = true
  Bullet.alert = true
  Bullet.rails_logger = true
end
```

**The association has a scope or condition:**
`includes` works with scoped associations. Define the scope on the association, not inline.

```ruby
# Model
has_many :active_line_items, -> { where(cancelled: false) }, class_name: "LineItem"

# Controller
Order.includes(:active_line_items)
```

**You preloaded but some records don't have the association:**
That's fine. `includes` handles empty associations gracefully — it just returns an empty collection. No error, no extra query.

**Deeply nested associations:**
Pass a hash to `includes` for nested preloading. Each level adds one query, not one query per record.

```ruby
Order.includes(line_items: { product: :category })
# 4 queries: orders, line_items, products, categories
```
