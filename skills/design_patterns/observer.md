# Design Pattern: Observer

## Pattern

Define a one-to-many dependency between objects so that when one object changes state, all its dependents are notified and updated automatically. In Rails, this replaces scattered callbacks with explicit, decoupled event handling.

```ruby
# Simple Ruby observer using ActiveSupport::Notifications (Rails built-in)

# PUBLISHER: fires events after key actions
class Orders::CreateService
  def call(params, user)
    order = user.orders.create!(params)

    # Publish event — doesn't know or care who's listening
    ActiveSupport::Notifications.instrument("order.created", order: order)

    Result.new(success: true, order: order)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success: false, order: e.record)
  end
end

# SUBSCRIBERS: each handles one concern, registered independently

# config/initializers/event_subscribers.rb
ActiveSupport::Notifications.subscribe("order.created") do |*, payload|
  order = payload[:order]
  OrderMailer.confirmation(order).deliver_later
end

ActiveSupport::Notifications.subscribe("order.created") do |*, payload|
  order = payload[:order]
  WarehouseNotificationJob.perform_later(order.id)
end

ActiveSupport::Notifications.subscribe("order.created") do |*, payload|
  order = payload[:order]
  Analytics.track("order_created", order_id: order.id, total: order.total)
end
```

Custom event system for more structure:

```ruby
# app/events/event_bus.rb
module EventBus
  SUBSCRIBERS = Hash.new { |h, k| h[k] = [] }

  def self.subscribe(event_name, handler)
    SUBSCRIBERS[event_name] << handler
  end

  def self.publish(event_name, **payload)
    SUBSCRIBERS[event_name].each do |handler|
      handler.call(**payload)
    rescue StandardError => e
      Rails.logger.error("EventBus: #{handler} failed for #{event_name}: #{e.message}")
      # Don't let one subscriber failure block others
    end
  end
end

# Subscriber classes — focused, testable
class OrderCreatedHandlers::SendConfirmation
  def self.call(order:)
    OrderMailer.confirmation(order).deliver_later
  end
end

class OrderCreatedHandlers::NotifyWarehouse
  def self.call(order:)
    WarehouseNotificationJob.perform_later(order.id)
  end
end

class OrderCreatedHandlers::TrackAnalytics
  def self.call(order:)
    Analytics.track("order_created", order_id: order.id, total: order.total)
  end
end

# Registration
EventBus.subscribe("order.created", OrderCreatedHandlers::SendConfirmation)
EventBus.subscribe("order.created", OrderCreatedHandlers::NotifyWarehouse)
EventBus.subscribe("order.created", OrderCreatedHandlers::TrackAnalytics)

# Publisher — fires and forgets
class Orders::CreateService
  def call(params, user)
    order = user.orders.create!(params)
    EventBus.publish("order.created", order: order)
    Result.new(success: true, order: order)
  end
end
```

## Why This Is Good

- **Publisher doesn't know its subscribers.** `CreateService` publishes "order.created" and moves on. It doesn't import, reference, or depend on mailers, warehouses, or analytics.
- **Adding new reactions doesn't modify existing code.** Sending a Slack notification on order creation? Add one subscriber. The publisher, the mailer subscriber, and the warehouse subscriber are untouched.
- **Each subscriber is independently testable.** Test `SendConfirmation.call(order: order)` in isolation — no service, no other subscribers.
- **Error isolation.** If analytics tracking fails, the email still sends and the warehouse still gets notified. One subscriber's failure doesn't cascade.
- **Replaces callback chains.** Instead of 5 `after_create` callbacks on the model, there are 5 focused subscriber classes registered in one place.

## Anti-Pattern

Using model callbacks as an implicit observer pattern:

```ruby
class Order < ApplicationRecord
  after_create :send_confirmation
  after_create :notify_warehouse
  after_create :track_analytics
  after_create :update_inventory
  after_create :award_loyalty_points

  private

  def send_confirmation
    OrderMailer.confirmation(self).deliver_later
  end

  def notify_warehouse
    WarehouseApi.notify(id: id)
  end

  # ... 30 more lines of callback methods
end
```

## Why This Is Bad

- **Tightly coupled.** Every subscriber is a method on the model. Adding a new reaction means modifying the model class.
- **Hidden execution order.** Callbacks run in declaration order, but that's not obvious. Reordering lines changes behavior silently.
- **Can't skip selectively.** Creating an order in seeds or tests triggers ALL callbacks. There's no way to say "create without notifications."
- **Transaction danger.** `after_create` runs inside the transaction. If `notify_warehouse` raises, the entire order creation rolls back.

## When To Apply

- **Multiple side effects triggered by one action.** An order is created → send email, notify warehouse, track analytics, update inventory. Each side effect is a subscriber.
- **Different teams own different reactions.** The billing team owns payment processing, the ops team owns warehouse notifications, the marketing team owns analytics. Each team's code is a separate subscriber.
- **You want to add/remove reactions without touching the core flow.** Feature flags can enable/disable subscribers without modifying the publisher.

## When NOT To Apply

- **One or two simple side effects.** If creating an order only sends one email, a direct call in the service object is clearer than an event bus.
- **Synchronous, transactional requirements.** If the side effect MUST succeed for the action to succeed (deducting credits must happen for the AI response to be valid), use direct calls within a transaction — not events.
- **Don't build an event bus for 3 events.** The overhead of a custom event system isn't justified until you have 10+ events with multiple subscribers each.

## Rails-Specific Alternatives

**`after_commit` for job enqueueing:**
If you want callback-style simplicity with event-style decoupling:

```ruby
class Order < ApplicationRecord
  after_commit :publish_created_event, on: :create

  private

  def publish_created_event
    OrderCreatedJob.perform_later(id)
  end
end

# The job dispatches to handlers
class OrderCreatedJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    OrderCreatedHandlers::SendConfirmation.call(order: order)
    OrderCreatedHandlers::NotifyWarehouse.call(order: order)
  end
end
```

This is pragmatic for small apps — it uses Rails conventions while keeping handlers extracted.
