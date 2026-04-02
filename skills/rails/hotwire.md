# Rails: Hotwire (Turbo + Stimulus)

## Pattern

Hotwire delivers fast, reactive UIs by sending HTML over the wire instead of JSON. Turbo handles navigation and page updates without JavaScript. Stimulus adds sprinkles of JS behavior when needed. Together, they replace most SPA complexity.

### Turbo Drive (Automatic)

```ruby
# Turbo Drive is automatic — every link click and form submission
# is intercepted and fetched via fetch(), replacing the body.
# No configuration needed. Just use standard Rails link and form helpers.

# The key contract: return proper HTTP status codes
class OrdersController < ApplicationController
  def create
    @order = current_user.orders.build(order_params)

    if @order.save
      redirect_to @order, notice: "Order created."  # 303 redirect → Turbo follows it
    else
      render :new, status: :unprocessable_entity  # 422 → Turbo replaces the page
    end
  end

  def update
    @order = current_user.orders.find(params[:id])

    if @order.update(order_params)
      redirect_to @order, notice: "Updated."
    else
      render :edit, status: :unprocessable_entity  # MUST return 422 for Turbo to re-render
    end
  end
end
```

### Turbo Frames (Partial Page Updates)

```erb
<%# app/views/orders/index.html.erb %>
<%# Only the content inside the turbo_frame is replaced on navigation %>
<h1>Orders</h1>

<%= turbo_frame_tag "orders_list" do %>
  <%= render @orders %>

  <%# Pagination links inside the frame only update the frame %>
  <%= paginate @orders %>
<% end %>

<%# Search form targets the frame %>
<%= form_with url: orders_path, method: :get, data: { turbo_frame: "orders_list" } do |f| %>
  <%= f.search_field :q, placeholder: "Search orders..." %>
  <%= f.submit "Search" %>
<% end %>
```

```erb
<%# app/views/orders/_order.html.erb %>
<%= turbo_frame_tag dom_id(order) do %>
  <div class="order-card">
    <h3><%= order.reference %></h3>
    <p><%= order.status %></p>
    <%= link_to "Edit", edit_order_path(order) %>
  </div>
<% end %>

<%# Clicking "Edit" loads the edit form INTO the frame — no full page load %>
```

```erb
<%# app/views/orders/edit.html.erb %>
<%= turbo_frame_tag dom_id(@order) do %>
  <%= render "form", order: @order %>
<% end %>
```

### Turbo Streams (Real-Time Updates)

```ruby
# After creating an order, broadcast updates to the page
class Order < ApplicationRecord
  after_create_commit -> {
    broadcast_prepend_to "orders",
      target: "orders_list",
      partial: "orders/order",
      locals: { order: self }
  }

  after_update_commit -> {
    broadcast_replace_to "orders",
      target: dom_id(self),
      partial: "orders/order",
      locals: { order: self }
  }

  after_destroy_commit -> {
    broadcast_remove_to "orders", target: dom_id(self)
  }
end
```

```erb
<%# app/views/orders/index.html.erb %>
<%= turbo_stream_from "orders" %>

<div id="orders_list">
  <%= render @orders %>
</div>
```

Inline Turbo Stream responses from controller actions:

```ruby
class OrdersController < ApplicationController
  def create
    @order = current_user.orders.build(order_params)

    if @order.save
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.prepend("orders_list",
            partial: "orders/order", locals: { order: @order })
        }
        format.html { redirect_to orders_path }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @order = current_user.orders.find(params[:id])
    @order.destroy!

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@order)) }
      format.html { redirect_to orders_path }
    end
  end
end
```

### Stimulus (Sprinkles of JavaScript)

```javascript
// app/javascript/controllers/toggle_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]

  toggle() {
    this.contentTarget.classList.toggle("hidden")
  }
}
```

```erb
<%# Usage in HTML — no inline JS, no jQuery %>
<div data-controller="toggle">
  <button data-action="click->toggle#toggle">Show Details</button>
  <div data-toggle-target="content" class="hidden">
    <p>Order details here...</p>
  </div>
</div>
```

```javascript
// app/javascript/controllers/auto_submit_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form"]

  submit() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => {
      this.formTarget.requestSubmit()
    }, 300)
  }
}
```

```erb
<%= form_with url: orders_path, method: :get,
    data: { controller: "auto-submit", auto_submit_target: "form", turbo_frame: "orders_list" } do |f| %>
  <%= f.search_field :q, data: { action: "input->auto-submit#submit" }, placeholder: "Search..." %>
<% end %>
```

## Why This Is Good

- **No JavaScript framework needed.** Turbo + Stimulus replaces 90% of what React/Vue do for typical CRUD apps, with far less code.
- **Server-rendered HTML.** No JSON API, no serializers, no client-side state management. The server renders HTML and Turbo delivers it to the right place.
- **Progressive enhancement.** Everything works without JavaScript (Turbo Drive degrades gracefully). Stimulus adds interactivity on top.
- **Turbo Streams enable real-time.** WebSocket-powered live updates without a single line of custom JavaScript. New orders appear instantly for all users.
- **Stimulus controllers are tiny.** 10-20 lines each, reusable across views, no build step complexity.

## Anti-Pattern

Disabling Turbo or fighting it:

```erb
<%# BAD: Disabling Turbo because forms don't work %>
<%= form_with model: @order, data: { turbo: false } do |f| %>

<%# The real fix: return the correct status code %>
def create
  if @order.save
    redirect_to @order       # 303 — Turbo follows
  else
    render :new, status: :unprocessable_entity  # 422 — Turbo re-renders
    # NOT: render :new (200 status makes Turbo think it succeeded)
  end
end
```

## When To Apply

- **Every new Rails 7+ app.** Hotwire is the default. Use it.
- **CRUD-heavy apps.** Forms, lists, search, pagination, inline editing — Hotwire handles all of these with minimal JavaScript.
- **Real-time features.** Chat, notifications, live dashboards — Turbo Streams over WebSockets.

## When NOT To Apply

- **Complex client-side interactions.** Drag-and-drop editors, canvas drawing, real-time collaboration — these may need a JavaScript framework.
- **Offline-first apps.** Turbo requires a server connection. PWAs with offline support need client-side state.
