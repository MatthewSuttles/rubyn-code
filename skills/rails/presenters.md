# Rails: Presenters / View Objects

## Pattern

When display logic accumulates in views, helpers, or models, extract it into a presenter — a plain Ruby object that wraps a model and adds formatting, display logic, and view-specific computed values. The model stays focused on data; the presenter handles how data is shown.

```ruby
# app/presenters/order_presenter.rb
class OrderPresenter < SimpleDelegator
  def formatted_total
    "$#{format('%.2f', total / 100.0)}"
  end

  def formatted_date
    created_at.strftime("%B %d, %Y")
  end

  def status_badge
    color = case status
            when "pending" then "yellow"
            when "confirmed" then "blue"
            when "shipped" then "indigo"
            when "delivered" then "green"
            when "cancelled" then "red"
            else "gray"
            end
    { text: status.titleize, color: color }
  end

  def shipping_estimate
    return "Delivered" if delivered?
    return "Cancelled" if cancelled?
    return "Ships within 24 hours" if confirmed?
    return "Processing" if pending?
    "Unknown"
  end

  def credit_card_display
    return "No card on file" unless user.default_payment_method
    "•••• #{user.default_payment_method.last_four}"
  end

  def line_item_count
    "#{line_items.count} #{'item'.pluralize(line_items.count)}"
  end

  def can_cancel?
    pending? || confirmed?
  end

  def can_edit?
    pending?
  end
end
```

```ruby
# Controller — wrap the model
class OrdersController < ApplicationController
  def show
    order = current_user.orders.includes(:line_items, :user).find(params[:id])
    @order = OrderPresenter.new(order)
  end

  def index
    orders = current_user.orders.recent.includes(:line_items)
    @orders = orders.map { |o| OrderPresenter.new(o) }
  end
end
```

```erb
<%# View — uses presenter methods, no logic in the template %>
<h1>Order <%= @order.reference %></h1>
<p>Placed: <%= @order.formatted_date %></p>
<p>Total: <%= @order.formatted_total %></p>
<p><%= @order.line_item_count %></p>

<span class="badge bg-<%= @order.status_badge[:color] %>">
  <%= @order.status_badge[:text] %>
</span>

<p><%= @order.shipping_estimate %></p>
<p>Payment: <%= @order.credit_card_display %></p>

<% if @order.can_cancel? %>
  <%= button_to "Cancel Order", order_cancellation_path(@order), method: :post %>
<% end %>
```

### SimpleDelegator Explained

```ruby
# SimpleDelegator forwards ALL method calls to the wrapped object
class OrderPresenter < SimpleDelegator
  # __getobj__ returns the wrapped Order
  # order.id, order.user, order.status — all work automatically
  # You only define methods for display-specific behavior

  def formatted_total
    "$#{format('%.2f', total / 100.0)}"  # `total` delegates to the Order
  end
end

presenter = OrderPresenter.new(order)
presenter.id            # Delegated to order.id
presenter.user          # Delegated to order.user
presenter.formatted_total  # Defined on presenter
presenter.is_a?(Order)  # true — SimpleDelegator preserves type
```

### Collection Presenter

```ruby
# app/presenters/order_collection_presenter.rb
class OrderCollectionPresenter
  include Enumerable

  def initialize(orders)
    @orders = orders
  end

  def each(&block)
    @orders.map { |o| OrderPresenter.new(o) }.each(&block)
  end

  def total_revenue
    "$#{format('%.2f', @orders.sum(:total) / 100.0)}"
  end

  def status_breakdown
    @orders.group(:status).count.transform_keys(&:titleize)
  end

  def empty_message
    "No orders yet. Your first order will appear here."
  end
end

# Controller
@orders = OrderCollectionPresenter.new(current_user.orders.recent)

# View
<p>Revenue: <%= @orders.total_revenue %></p>
<% @orders.each do |order| %>
  <p><%= order.formatted_total %></p>
<% end %>
```

## Why This Is Good

- **Models stay clean.** `Order` doesn't need `formatted_total`, `status_badge`, or `shipping_estimate`. Those are display concerns, not data concerns.
- **Views stay logic-free.** No `<% if order.status == "pending" || order.status == "confirmed" %>` in templates. Just `<% if @order.can_cancel? %>`.
- **Testable.** `OrderPresenter.new(build_stubbed(:order, total: 19_99)).formatted_total` — fast, isolated, no views or controllers needed.
- **Reusable across formats.** The same presenter works in HTML views, JSON serializers, mailer templates, and PDF generators.
- **`SimpleDelegator` is transparent.** The presenter IS the order for all purposes — it responds to every Order method. No explicit delegation for each attribute.

## Anti-Pattern

Display logic in the model or scattered across helpers:

```ruby
# BAD: Display logic on the model
class Order < ApplicationRecord
  def formatted_total
    "$#{format('%.2f', total / 100.0)}"
  end

  def status_color
    case status
    when "pending" then "yellow"
    when "shipped" then "blue"
    end
  end

  def display_date
    created_at.strftime("%B %d, %Y")
  end
end
# The model now knows about dollar signs, colors, and date formatting

# BAD: Logic in helpers (global namespace, hard to find, hard to test)
module OrdersHelper
  def order_status_badge(order)
    color = order.status == "pending" ? "yellow" : "green"
    content_tag(:span, order.status.titleize, class: "badge bg-#{color}")
  end
end

# BAD: Logic in views
<% if order.total > 200_00 %>
  <span class="badge bg-gold">VIP Order</span>
<% end %>
<% if order.created_at > 30.days.ago %>
  <span>Recent</span>
<% end %>
```

## When To Apply

- **A model has 3+ methods that only exist for display purposes.** `formatted_total`, `display_name`, `status_label` — these are presenter methods.
- **Views have conditional logic based on model state.** `if order.pending? || order.confirmed?` → extract to `presenter.can_cancel?`.
- **The same formatting appears in multiple views.** An order's total is formatted in the index, show, email, and PDF. One presenter method, used everywhere.
- **Helper files are becoming catch-alls.** If `OrdersHelper` has 15 methods, it's a presenter in disguise.

## When NOT To Apply

- **One or two simple formatting methods.** If the model only has `def to_s; name; end`, that's fine on the model. Don't create a presenter for one method.
- **Rails built-in helpers suffice.** `number_to_currency(order.total)` in a view is fine for a single use. A presenter is for when you're repeating the same formatting logic.
- **API-only apps.** Use serializers instead of presenters. Serializers control the JSON output; presenters control HTML display. Different tools for different formats.

## Edge Cases

**Presenter + form helpers:**
`SimpleDelegator` preserves the wrapped object's class, so `form_with model: @order` works even when `@order` is an `OrderPresenter`. Rails form helpers use the underlying model for URL generation and param naming.

**Presenter in serializers (API):**
Don't use presenters in JSON APIs. Use a dedicated serializer class instead — it controls the exact shape of the JSON output without inheriting display-specific methods.

**Nested presenters:**
```ruby
class OrderPresenter < SimpleDelegator
  def presented_line_items
    line_items.map { |li| LineItemPresenter.new(li) }
  end
end
```

**Alternative: Plain class instead of SimpleDelegator:**
```ruby
class OrderPresenter
  attr_reader :order
  delegate :id, :reference, :status, :user, :line_items, :created_at, to: :order

  def initialize(order)
    @order = order
  end

  def formatted_total
    "$#{format('%.2f', order.total / 100.0)}"
  end
end
```
This is more explicit (you declare exactly which methods delegate) but more verbose. Use `SimpleDelegator` unless you need to restrict the interface.
