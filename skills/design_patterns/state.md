# Design Pattern: State

## Pattern

Allow an object to change its behavior when its internal state changes by delegating to state objects. Instead of `case` statements on a status field, each state is a class that defines the valid transitions and behavior for that state.

```ruby
# State classes — each defines what's possible in that state
module OrderStates
  class Pending
    def confirm(order)
      return Result.new(success: false, error: "No items") if order.line_items.empty?

      order.update!(status: :confirmed, confirmed_at: Time.current)
      OrderMailer.confirmed(order).deliver_later
      Result.new(success: true)
    end

    def cancel(order, reason:)
      order.update!(status: :cancelled, cancelled_at: Time.current, cancel_reason: reason)
      Result.new(success: true)
    end

    def ship(_order) = Result.new(success: false, error: "Cannot ship a pending order")
    def deliver(_order) = Result.new(success: false, error: "Cannot deliver a pending order")
  end

  class Confirmed
    def confirm(_order) = Result.new(success: false, error: "Already confirmed")

    def ship(order)
      order.update!(status: :shipped, shipped_at: Time.current)
      OrderMailer.shipped(order).deliver_later
      Result.new(success: true)
    end

    def cancel(order, reason:)
      order.update!(status: :cancelled, cancelled_at: Time.current, cancel_reason: reason)
      Orders::RefundService.call(order)
      Result.new(success: true)
    end

    def deliver(_order) = Result.new(success: false, error: "Must ship before delivering")
  end

  class Shipped
    def confirm(_order) = Result.new(success: false, error: "Already shipped")
    def ship(_order) = Result.new(success: false, error: "Already shipped")
    def cancel(_order, reason: nil) = Result.new(success: false, error: "Cannot cancel shipped order")

    def deliver(order)
      order.update!(status: :delivered, delivered_at: Time.current)
      OrderMailer.delivered(order).deliver_later
      Result.new(success: true)
    end
  end

  class Delivered
    def confirm(_order) = Result.new(success: false, error: "Already delivered")
    def ship(_order) = Result.new(success: false, error: "Already delivered")
    def cancel(_order, reason: nil) = Result.new(success: false, error: "Cannot cancel delivered order")
    def deliver(_order) = Result.new(success: false, error: "Already delivered")
  end

  class Cancelled
    def confirm(_order) = Result.new(success: false, error: "Order is cancelled")
    def ship(_order) = Result.new(success: false, error: "Order is cancelled")
    def cancel(_order, reason: nil) = Result.new(success: false, error: "Already cancelled")
    def deliver(_order) = Result.new(success: false, error: "Order is cancelled")
  end

  MAPPING = {
    "pending" => Pending.new,
    "confirmed" => Confirmed.new,
    "shipped" => Shipped.new,
    "delivered" => Delivered.new,
    "cancelled" => Cancelled.new
  }.freeze

  def self.for(status)
    MAPPING.fetch(status)
  end
end

# The Order delegates state-dependent behavior
class Order < ApplicationRecord
  def current_state
    OrderStates.for(status)
  end

  def confirm!
    current_state.confirm(self)
  end

  def ship!
    current_state.ship(self)
  end

  def cancel!(reason:)
    current_state.cancel(self, reason: reason)
  end

  def deliver!
    current_state.deliver(self)
  end
end

# Usage is clean and safe
order = Order.find(params[:id])
result = order.confirm!           # Works when pending
result = order.ship!              # Works when confirmed
result = order.cancel!(reason: "changed mind")  # Invalid when shipped
# result.success? => false, result.error => "Cannot cancel shipped order"
```

## Why This Is Good

- **Invalid transitions return errors, not crashes.** Calling `ship!` on a pending order returns a descriptive error instead of silently doing nothing or raising an exception.
- **Each state's rules are visible in one place.** Open `Confirmed` to see everything that can happen from the confirmed state. No scanning a 200-line model for scattered `if status == "confirmed"` checks.
- **Adding a new state means adding one class.** A `Refunded` state is one new class with 4 methods. Existing states don't change.
- **Testable per state.** Test `Pending#confirm` in isolation — does it update status, send email, return success? Test `Shipped#cancel` — does it return the right error?

## Anti-Pattern

A case/when on status scattered throughout the model:

```ruby
class Order < ApplicationRecord
  def confirm!
    case status
    when "pending"
      update!(status: :confirmed, confirmed_at: Time.current)
      OrderMailer.confirmed(self).deliver_later
    when "confirmed"
      raise "Already confirmed"
    when "shipped", "delivered"
      raise "Cannot confirm — already #{status}"
    when "cancelled"
      raise "Cannot confirm cancelled order"
    end
  end

  def ship!
    case status
    when "confirmed"
      update!(status: :shipped, shipped_at: Time.current)
    when "pending"
      raise "Must confirm first"
    # ... another 10 lines of case/when
    end
  end

  def cancel!
    case status
    when "pending", "confirmed"
      update!(status: :cancelled)
      Orders::RefundService.call(self) if status == "confirmed"
    when "shipped"
      raise "Cannot cancel shipped order"
    # ... more branching
    end
  end
end
```

## Why This Is Bad

- **N methods × M states = N×M branches.** 4 actions × 5 states = 20 case branches scattered across 4 methods. Adding a 6th state means editing all 4 methods.
- **Rules for one state are split across multiple methods.** To understand "what can a confirmed order do?" you read `confirm!`, `ship!`, `cancel!`, and `deliver!` — scanning for `when "confirmed"` in each.
- **Inconsistent error handling.** Some branches raise, some return nil, some silently do nothing. The State pattern enforces a consistent return type (`Result`).

## When To Apply

- **An object has 3+ states with different behavior.** Orders (pending/confirmed/shipped/delivered/cancelled), subscriptions (trialing/active/past_due/cancelled), projects (draft/active/archived).
- **You find yourself writing `case status` or `if object.pending?` in multiple places.** That's the State pattern trying to emerge.
- **State transitions have side effects.** Confirming sends an email, shipping notifies the warehouse, cancelling triggers a refund. Each state's transitions have different side effects.

## When NOT To Apply

- **Two states with simple behavior.** An `active`/`inactive` boolean with one behavior difference doesn't need state objects. A simple `if active?` is clearer.
- **Status is display-only.** If the status field only affects what badge is shown in the UI, a helper method or enum is sufficient.
- **The team uses `aasm` or `statesman` gems.** Follow existing conventions. These gems implement the State pattern with DSL sugar.

## Edge Cases

**State machine gems vs hand-rolled:**
For simple state machines (3-5 states, clear transitions), hand-rolled state objects are clearer. For complex machines (10+ states, guards, audit trails), consider `statesman` or `aasm`.

**Querying by state:**
State objects handle behavior. Database queries use the status column directly:

```ruby
scope :actionable, -> { where(status: %w[pending confirmed]) }
scope :completed, -> { where(status: %w[delivered cancelled]) }
```

**Persisting state transitions for audit:**

```ruby
class OrderStates::Confirmed
  def ship(order)
    order.update!(status: :shipped, shipped_at: Time.current)
    order.state_transitions.create!(from: "confirmed", to: "shipped", actor: Current.user)
    Result.new(success: true)
  end
end
```
