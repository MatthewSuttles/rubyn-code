# Rails: ActionCable (WebSockets)

## Pattern

ActionCable integrates WebSockets into Rails for real-time features — live chat, notifications, live updates, and collaborative editing. Use channels for bi-directional communication and Turbo Streams for server-pushed HTML updates.

```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      if (user = User.find_by(id: cookies.encrypted[:user_id]))
        user
      else
        reject_unauthorized_connection
      end
    end
  end
end
```

```ruby
# app/channels/order_updates_channel.rb
class OrderUpdatesChannel < ApplicationCable::Channel
  def subscribed
    order = current_user.orders.find(params[:order_id])
    stream_for order
  end

  def unsubscribed
    # Cleanup when client disconnects
  end
end

# Broadcasting from anywhere in the app
OrderUpdatesChannel.broadcast_to(order, {
  type: "status_changed",
  status: order.status,
  updated_at: order.updated_at.iso8601
})
```

### Turbo Streams over ActionCable (The Rails 7+ Way)

```ruby
# Model broadcasts — simplest approach
class Order < ApplicationRecord
  after_create_commit -> { broadcast_prepend_to "orders", target: "orders_list" }
  after_update_commit -> { broadcast_replace_to "orders" }
  after_destroy_commit -> { broadcast_remove_to "orders" }
end

# Or broadcast from a service object (preferred — keeps model clean)
class Orders::ShipService
  def call(order)
    order.update!(status: :shipped, shipped_at: Time.current)

    # Push update to all subscribers
    Turbo::StreamsChannel.broadcast_replace_to(
      "order_#{order.id}",
      target: "order_#{order.id}",
      partial: "orders/order",
      locals: { order: order }
    )

    # Push to the orders list page too
    Turbo::StreamsChannel.broadcast_replace_to(
      "orders",
      target: "order_#{order.id}",
      partial: "orders/order_row",
      locals: { order: order }
    )
  end
end
```

```erb
<%# View — subscribe to updates %>
<%= turbo_stream_from "orders" %>

<div id="orders_list">
  <%= render @orders %>
</div>

<%# Individual order page %>
<%= turbo_stream_from "order_#{@order.id}" %>

<div id="order_<%= @order.id %>">
  <%= render @order %>
</div>
```

### Custom Channel for Interactive Features

```ruby
# app/channels/notifications_channel.rb
class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    stream_for current_user
  end
end

# Send notifications from anywhere
class NotificationService
  def self.push(user, message:, type: :info)
    NotificationsChannel.broadcast_to(user, {
      type: type,
      message: message,
      timestamp: Time.current.iso8601
    })
  end
end

# Usage
NotificationService.push(user, message: "Your order shipped!", type: :success)
```

```javascript
// app/javascript/channels/notifications_channel.js
import consumer from "./consumer"

consumer.subscriptions.create("NotificationsChannel", {
  received(data) {
    const toast = document.createElement("div")
    toast.className = `toast toast-${data.type}`
    toast.textContent = data.message
    document.getElementById("notifications").appendChild(toast)

    setTimeout(() => toast.remove(), 5000)
  }
})
```

## Why This Is Good

- **Turbo Streams over ActionCable is zero-JavaScript real-time.** Server pushes HTML, Turbo applies it. No custom JS for most use cases.
- **`broadcast_to` uses the model as the channel key.** `stream_for order` and `broadcast_to(order, ...)` — the channel routing is automatic and scoped.
- **Authentication via cookies.** The WebSocket connection inherits the user's session. No separate auth token needed for web apps.
- **Scales with Redis.** In production, ActionCable uses Redis as the pub/sub backend. Multiple app servers share the same broadcast channel.

## When To Apply

- **Live updates** — order status changes, dashboard metrics, admin activity feeds.
- **Notifications** — real-time toasts, badge counts, alert banners.
- **Collaborative features** — shared editing, presence indicators, live cursors.
- **Turbo Stream broadcasts** — the simplest path. Use this before building custom channels.

## When NOT To Apply

- **Polling works fine.** If data changes once per minute and freshness isn't critical, a 30-second poll is simpler than WebSockets.
- **API-only apps without a frontend.** Use webhooks or SSE instead.
- **High-frequency data streams** (stock tickers, game state at 60fps). ActionCable adds overhead per message — consider a dedicated WebSocket server.
