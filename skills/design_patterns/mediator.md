# Design Pattern: Mediator

## Pattern

Reduce chaotic dependencies between objects by centralizing communication through a mediator. Instead of objects referencing each other directly, they communicate through the mediator, which coordinates the interaction.

In Rails, this maps to orchestrator services that coordinate multiple subsystems without those subsystems knowing about each other.

```ruby
# Without Mediator: Objects reference each other directly
# Order knows about Inventory, Payment, Notification, Analytics
# Inventory knows about Order, Notification
# Payment knows about Order, Notification, Analytics
# Everything is coupled to everything

# With Mediator: One orchestrator coordinates everything
class Orders::CheckoutMediator
  def initialize(
    inventory: Inventory::ReservationService.new,
    payment: Payments::ChargeService.new,
    notification: Notifications::Dispatcher.new,
    analytics: Analytics::Tracker.new
  )
    @inventory = inventory
    @payment = payment
    @notification = notification
    @analytics = analytics
  end

  def checkout(order, payment_method)
    # Step 1: Reserve inventory
    reservation = @inventory.reserve(order.line_items)
    unless reservation.success?
      return Result.new(success: false, error: "Items unavailable: #{reservation.error}")
    end

    # Step 2: Charge payment
    charge = @payment.charge(order.total_cents, payment_method.token)
    unless charge.success?
      @inventory.release(reservation.id)  # Compensate
      return Result.new(success: false, error: "Payment failed: #{charge.error}")
    end

    # Step 3: Confirm order
    order.update!(
      status: :confirmed,
      confirmed_at: Time.current,
      payment_transaction_id: charge.transaction_id
    )

    # Step 4: Side effects (non-critical)
    @notification.dispatch(order.user, "Order #{order.reference} confirmed!")
    @analytics.track("checkout_completed", order_id: order.id, total: order.total)

    Result.new(success: true, order: order)
  rescue StandardError => e
    # Compensate on unexpected failure
    @inventory.release(reservation&.id) if reservation&.success?
    @payment.refund(charge.transaction_id) if charge&.success?
    raise
  end
end

# Each service is independent — none knows about the others
class Inventory::ReservationService
  def reserve(line_items)
    # Only knows about inventory
  end

  def release(reservation_id)
    # Only knows about inventory
  end
end

class Payments::ChargeService
  def charge(amount_cents, token)
    # Only knows about payments
  end

  def refund(transaction_id)
    # Only knows about payments
  end
end
```

## Why This Is Good

- **Subsystems are decoupled.** `Inventory::ReservationService` doesn't know about payments. `Payments::ChargeService` doesn't know about notifications. Each can be developed, tested, and deployed independently.
- **The workflow is visible in one place.** Open `CheckoutMediator` and read the entire checkout flow: reserve → charge → confirm → notify → track. The orchestration logic is centralized.
- **Compensation logic is explicit.** If payment fails, inventory is released. If anything unexpected happens, both are rolled back. This saga-style coordination is easy to reason about when it's in one mediator.
- **Easy to modify the flow.** Adding fraud detection between reserve and charge means adding one step in the mediator. No other services change.
- **Testable with injected doubles.** Each service is injected, so tests can verify the orchestration without real inventory, payments, or notifications.

## Anti-Pattern

Objects communicating directly, creating a web of dependencies:

```ruby
# BAD: Order model orchestrates everything
class Order < ApplicationRecord
  after_create :reserve_inventory
  after_create :charge_payment
  after_create :send_notification
  after_create :track_analytics

  private

  def reserve_inventory
    Inventory::ReservationService.new.reserve(line_items)
  end

  def charge_payment
    result = Payments::ChargeService.new.charge(total_cents, user.default_payment_method.token)
    unless result.success?
      Inventory::ReservationService.new.release(inventory_reservation_id)
      raise "Payment failed"
    end
  end
  # ... Order knows about EVERY subsystem
end
```

## When To Apply

- **Multi-step workflows** — checkout, registration, order fulfillment, onboarding. Any flow that touches 3+ subsystems.
- **When objects are becoming too interconnected.** If Service A calls Service B which calls Service C which calls Service A, you need a mediator to break the cycle.
- **Saga/compensation patterns.** When steps must be rolled back if later steps fail, a mediator manages the compensation logic.

## When NOT To Apply

- **Two objects communicating.** A service calling one other service doesn't need a mediator. That's just a method call.
- **Event-driven communication works better.** If subsystems don't need coordination (just fire-and-forget), use the Observer pattern instead.
- **The mediator becomes a god object.** If the mediator is 500 lines with 20 dependencies, split it into smaller mediators for sub-workflows.
