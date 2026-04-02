# Rails: Caching

## Pattern

Cache at the right layer for the right duration. Rails provides fragment caching (views), low-level caching (arbitrary data), Russian doll caching (nested fragments), and HTTP caching (ETags). Use the cheapest cache that satisfies the freshness requirement.

### Low-Level Caching (Most Versatile)

```ruby
# Cache expensive queries or computations
class DashboardService
  def call(user)
    {
      order_count: cached_order_count(user),
      revenue: cached_revenue(user),
      top_products: cached_top_products(user)
    }
  end

  private

  def cached_order_count(user)
    Rails.cache.fetch("dashboard:#{user.id}:order_count", expires_in: 15.minutes) do
      user.orders.count
    end
  end

  def cached_revenue(user)
    Rails.cache.fetch("dashboard:#{user.id}:revenue", expires_in: 15.minutes) do
      user.orders.shipped.sum(:total)
    end
  end

  def cached_top_products(user)
    Rails.cache.fetch("dashboard:#{user.id}:top_products", expires_in: 1.hour) do
      user.orders
        .joins(line_items: :product)
        .group("products.name")
        .order("count_all DESC")
        .limit(5)
        .count
    end
  end
end
```

### Cache Key Design

```ruby
# Key-based expiration — cache auto-expires when the record changes
class Order < ApplicationRecord
  def cache_key_with_version
    "orders/#{id}-#{updated_at.to_i}"
  end
end

# Collection cache keys
Rails.cache.fetch(["v1/orders", current_user.orders.cache_key_with_version]) do
  current_user.orders.includes(:line_items).map(&:as_json)
end

# Manual invalidation when needed
def invalidate_dashboard_cache(user)
  Rails.cache.delete_matched("dashboard:#{user.id}:*")
end
```

### Fragment Caching (Views)

```erb
<%# Russian doll caching — outer cache wraps inner caches %>
<% cache @order do %>
  <h2><%= @order.reference %></h2>
  <p>Total: <%= number_to_currency(@order.total / 100.0) %></p>

  <% @order.line_items.each do |item| %>
    <%# Inner cache — only re-renders if item changes %>
    <% cache item do %>
      <div class="line-item">
        <%= item.product.name %> x <%= item.quantity %>
      </div>
    <% end %>
  <% end %>
<% end %>
```

### HTTP Caching

```ruby
class Api::V1::ProductsController < Api::V1::BaseController
  # ETag-based — returns 304 Not Modified if content hasn't changed
  def show
    product = Product.find(params[:id])

    if stale?(product)
      render json: ProductSerializer.new(product).as_json
    end
  end

  # Time-based — client caches for the specified duration
  def index
    expires_in 5.minutes, public: true

    products = Product.active.order(:name)
    render json: products.map { |p| ProductSerializer.new(p).as_json }
  end
end
```

### Counter Caches (Database-Level Caching)

```ruby
# Migration
add_column :users, :orders_count, :integer, default: 0, null: false

# Model
class Order < ApplicationRecord
  belongs_to :user, counter_cache: true
end

# Now user.orders_count is a column read, not a COUNT(*) query
# Updated automatically on Order create/destroy
```

## Why This Is Good

- **`Rails.cache.fetch` is atomic.** If the cache misses, the block runs, and the result is stored. No race conditions between check and set.
- **Key-based expiration is self-managing.** `"orders/#{id}-#{updated_at.to_i}"` automatically expires when the record is updated. No manual invalidation needed.
- **Russian doll caching is granular.** When one line item changes, only that item's fragment re-renders. The order fragment and other items serve from cache.
- **HTTP caching offloads the server.** ETags and `expires_in` let browsers and CDNs serve cached responses without hitting your app at all.
- **Counter caches eliminate N+1 counts.** Displaying `user.orders_count` for 50 users is 0 queries instead of 50.

## Anti-Pattern

Caching without expiration or invalidation:

```ruby
# BAD: Cache forever with no expiration
Rails.cache.write("all_products", Product.all.to_a)  # Never expires, grows stale

# BAD: Over-caching mutable data
Rails.cache.fetch("user:#{user.id}", expires_in: 24.hours) do
  user.attributes  # User could change their email, name, plan in 24 hours
end
```

## When To Apply

- **Expensive queries displayed on every page load.** Dashboard counts, leaderboards, aggregate stats.
- **Rarely-changing reference data.** Product catalogs, category trees, configuration.
- **API responses that many clients request.** HTTP caching with CDNs.
- **View fragments with complex rendering.** Partial renders that involve multiple queries or helpers.

## When NOT To Apply

- **Data that must be real-time.** Account balances, stock levels, live order status. Stale caches here cause user-visible bugs.
- **Simple queries that are already fast.** Caching a `find_by(id:)` that takes 1ms adds complexity without meaningful speedup.
- **In development.** Enable caching in development only when actively debugging cache behavior: `rails dev:cache`.
