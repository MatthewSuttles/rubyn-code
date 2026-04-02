# Rails: Serializers

## Pattern

Serializers control the exact shape of your JSON API responses. They decouple the API surface from the database schema, prevent accidental exposure of internal fields, and provide a single place to manage field inclusion, formatting, and nested associations.

### Manual Serializer (Simplest, No Gems)

```ruby
# app/serializers/order_serializer.rb
class OrderSerializer
  def initialize(order)
    @order = order
  end

  def as_json(*)
    {
      id: @order.id,
      reference: @order.reference,
      status: @order.status,
      total_cents: @order.total,
      total_formatted: format_currency(@order.total),
      shipping_address: @order.shipping_address,
      line_items: serialize_line_items,
      created_at: @order.created_at.iso8601,
      updated_at: @order.updated_at.iso8601
    }
  end

  private

  def serialize_line_items
    @order.line_items.map do |item|
      {
        id: item.id,
        product_name: item.product.name,
        quantity: item.quantity,
        unit_price_cents: item.unit_price,
        total_cents: item.quantity * item.unit_price
      }
    end
  end

  def format_currency(cents)
    "$#{format('%.2f', cents / 100.0)}"
  end
end

# Controller usage
class Api::V1::OrdersController < Api::V1::BaseController
  def show
    order = current_user.orders.includes(line_items: :product).find(params[:id])
    render json: { order: OrderSerializer.new(order).as_json }
  end

  def index
    orders = current_user.orders.includes(line_items: :product).recent
    render json: {
      orders: orders.map { |o| OrderSerializer.new(o).as_json },
      meta: pagination_meta(orders)
    }
  end
end
```

### Collection Serializer Helper

```ruby
# app/serializers/base_serializer.rb
class BaseSerializer
  def initialize(object)
    @object = object
  end

  def as_json(*)
    raise NotImplementedError
  end

  # Class method for serializing collections
  def self.collection(objects)
    objects.map { |obj| new(obj).as_json }
  end
end

class OrderSerializer < BaseSerializer
  def as_json(*)
    {
      id: @object.id,
      reference: @object.reference,
      status: @object.status,
      total_cents: @object.total,
      created_at: @object.created_at.iso8601
    }
  end
end

# Usage
render json: { orders: OrderSerializer.collection(orders) }
```

### Conditional Fields and Includes

```ruby
class OrderSerializer
  def initialize(order, includes: [])
    @order = order
    @includes = includes.map(&:to_sym)
  end

  def as_json(*)
    data = {
      id: @order.id,
      reference: @order.reference,
      status: @order.status,
      total_cents: @order.total,
      created_at: @order.created_at.iso8601
    }

    data[:line_items] = serialize_line_items if include?(:line_items)
    data[:user] = serialize_user if include?(:user)
    data[:shipment] = serialize_shipment if include?(:shipment)

    data
  end

  private

  def include?(association)
    @includes.include?(association)
  end

  def serialize_line_items
    @order.line_items.map { |li| LineItemSerializer.new(li).as_json }
  end

  def serialize_user
    UserSerializer.new(@order.user).as_json
  end

  def serialize_shipment
    return nil unless @order.shipment
    ShipmentSerializer.new(@order.shipment).as_json
  end
end

# Controller — caller decides what to include
def show
  order = current_user.orders.find(params[:id])
  includes = (params[:include] || "").split(",").map(&:strip)

  # Preload only what's requested
  order = preload_includes(order, includes)

  render json: { order: OrderSerializer.new(order, includes: includes).as_json }
end
```

### Jbuilder (Rails Built-In)

```ruby
# app/views/api/v1/orders/show.json.jbuilder
json.order do
  json.id @order.id
  json.reference @order.reference
  json.status @order.status
  json.total_cents @order.total
  json.total_formatted number_to_currency(@order.total / 100.0)
  json.created_at @order.created_at.iso8601

  json.line_items @order.line_items do |item|
    json.id item.id
    json.product_name item.product.name
    json.quantity item.quantity
    json.unit_price_cents item.unit_price
  end
end

# app/views/api/v1/orders/index.json.jbuilder
json.orders @orders do |order|
  json.partial! "api/v1/orders/order", order: order
end
json.meta do
  json.total_count @orders.total_count
  json.current_page @orders.current_page
end
```

## Why This Is Good

- **API surface is explicit.** The serializer lists every field the API returns. Adding or removing a field is a one-line change in one file.
- **No accidental exposure.** `render json: @order` would expose `password_digest`, `internal_notes`, `api_cost_usd`, and every other column. Serializers whitelist only the fields clients should see.
- **Formatting is centralized.** Dates are always ISO8601, money is always in cents with a formatted version, statuses are always lowercase. Clients get consistent data shapes.
- **Nested associations are controlled.** You decide how deep the nesting goes. Clients can request includes, but you control what's available.
- **Testable.** `OrderSerializer.new(order).as_json` returns a hash you can assert on without HTTP.

## Anti-Pattern

```ruby
# BAD: Rendering the model directly
render json: @order
# Exposes EVERYTHING: password_digest, internal_notes, admin fields, timestamps you don't want

# BAD: Inline hash construction in the controller
render json: {
  id: @order.id,
  ref: @order.reference,  # Inconsistent naming
  total: "$#{@order.total / 100.0}",  # Formatting in controller
  items: @order.line_items.map { |li| { name: li.product.name, qty: li.quantity } }
}
# Repeated in every controller, inconsistent across endpoints

# BAD: as_json override on the model
class Order < ApplicationRecord
  def as_json(options = {})
    super(only: [:id, :reference, :status, :total], include: { line_items: { only: [:id, :quantity] } })
  end
end
# Now EVERY json render uses this shape — can't have different shapes for different endpoints
```

## When To Apply

- **Every JSON API endpoint.** No exceptions. Even a simple `{ id: 1, name: "test" }` should go through a serializer once you have more than 2 API endpoints.
- **When different endpoints need different shapes.** A list endpoint shows `id, reference, status, total`. A detail endpoint adds `line_items, user, shipment`. Serializers with `includes:` handle this cleanly.
- **When you need versioning.** `Api::V1::OrderSerializer` and `Api::V2::OrderSerializer` can coexist. Can't do that with `as_json` on the model.

## When NOT To Apply

- **HTML-only apps.** Views render HTML directly from models/presenters. Serializers are for JSON APIs.
- **Single internal endpoint.** A health check returning `{ status: "ok" }` doesn't need a serializer class.
- **GraphQL.** GraphQL types serve the same purpose as serializers. Don't layer serializers on top of GraphQL.

## Gem Alternatives

| Approach | Pros | Cons |
|---|---|---|
| Manual class | Zero dependencies, full control, simplest | More boilerplate for large APIs |
| Jbuilder | Ships with Rails, template-based | Slower (renders views), harder to test |
| `jsonapi-serializer` | JSON:API compliant, relationships, sparse fieldsets | Heavy for simple APIs |
| `alba` | Fast, flexible, modern | Another dependency |
| `blueprinter` | Declarative DSL, views, associations | Another dependency |

**Recommendation:** Start with manual serializers. They're fast, testable, and dependency-free. Switch to a gem only when you have 20+ serializers and need features like sparse fieldsets or JSON:API compliance.
