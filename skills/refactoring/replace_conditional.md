# Refactoring: Replace Conditional with Polymorphism

## Pattern

When a `case/when` or `if/elsif` chain switches on a type to determine behavior, replace it with polymorphic objects. Each branch becomes a class that implements the same interface.

```ruby
# BEFORE: case/when switches on type to determine pricing
class SubscriptionBiller
  def monthly_charge(subscription)
    case subscription.plan
    when "free"
      0
    when "pro"
      19_00
    when "team"
      base = 49_00
      extra_seats = [subscription.seats - 5, 0].max
      base + (extra_seats * 10_00)
    when "enterprise"
      custom_price = subscription.negotiated_price
      custom_price || 199_00
    end
  end

  def usage_limit(subscription)
    case subscription.plan
    when "free" then 30
    when "pro" then 1_000
    when "team" then 5_000
    when "enterprise" then Float::INFINITY
    end
  end

  def features(subscription)
    case subscription.plan
    when "free" then [:basic_ai]
    when "pro" then [:basic_ai, :pro_mode, :export]
    when "team" then [:basic_ai, :pro_mode, :export, :team_sharing, :admin_panel]
    when "enterprise" then [:basic_ai, :pro_mode, :export, :team_sharing, :admin_panel, :sso, :audit_log]
    end
  end
end
```

```ruby
# AFTER: Each plan is a class with its own behavior
module Plans
  class Free
    def monthly_charge(_subscription) = 0
    def usage_limit = 30
    def features = [:basic_ai]
  end

  class Pro
    def monthly_charge(_subscription) = 19_00
    def usage_limit = 1_000
    def features = [:basic_ai, :pro_mode, :export]
  end

  class Team
    def monthly_charge(subscription)
      base = 49_00
      extra_seats = [subscription.seats - 5, 0].max
      base + (extra_seats * 10_00)
    end

    def usage_limit = 5_000
    def features = [:basic_ai, :pro_mode, :export, :team_sharing, :admin_panel]
  end

  class Enterprise
    def monthly_charge(subscription)
      subscription.negotiated_price || 199_00
    end

    def usage_limit = Float::INFINITY
    def features = [:basic_ai, :pro_mode, :export, :team_sharing, :admin_panel, :sso, :audit_log]
  end

  REGISTRY = {
    "free" => Free.new,
    "pro" => Pro.new,
    "team" => Team.new,
    "enterprise" => Enterprise.new
  }.freeze

  def self.for(plan_name)
    REGISTRY.fetch(plan_name)
  end
end

# Subscription delegates to its plan
class Subscription < ApplicationRecord
  def plan_object
    Plans.for(plan)
  end

  def monthly_charge
    plan_object.monthly_charge(self)
  end

  def usage_limit
    plan_object.usage_limit
  end

  def features
    plan_object.features
  end
end
```

## Why This Is Good

- **Adding a new plan doesn't modify existing code.** A "Starter" plan means one new class. `Free`, `Pro`, `Team`, and `Enterprise` are untouched.
- **All behavior for one plan is in one place.** Open `Plans::Team` to see pricing, limits, and features together. No scanning across three `case` statements.
- **Each plan is independently testable.** `Plans::Team.new.monthly_charge(sub_with_10_seats)` — no branching, no other plans involved.
- **Eliminates the "parallel case statements" code smell.** Three methods all switching on `subscription.plan` is a sign that `plan` wants to be an object.

# Refactoring: Replace Nested Conditional with Guard Clauses

## Pattern

When a method has deep nesting or complex conditional logic, use guard clauses to handle edge cases and error conditions early, leaving the main logic un-nested.

```ruby
# BEFORE: Deep nesting
def process_payment(order)
  if order.present?
    if order.total > 0
      if order.user.payment_method.present?
        if order.user.payment_method.valid?
          result = PaymentGateway.charge(order.user.payment_method, order.total)
          if result.success?
            order.update!(paid: true)
            { success: true, transaction_id: result.id }
          else
            { success: false, error: result.error_message }
          end
        else
          { success: false, error: "Invalid payment method" }
        end
      else
        { success: false, error: "No payment method on file" }
      end
    else
      { success: false, error: "Order total must be positive" }
    end
  else
    { success: false, error: "Order not found" }
  end
end
```

```ruby
# AFTER: Guard clauses handle edge cases first
def process_payment(order)
  return { success: false, error: "Order not found" } unless order
  return { success: false, error: "Order total must be positive" } unless order.total > 0
  return { success: false, error: "No payment method on file" } unless order.user.payment_method
  return { success: false, error: "Invalid payment method" } unless order.user.payment_method.valid?

  result = PaymentGateway.charge(order.user.payment_method, order.total)

  return { success: false, error: result.error_message } unless result.success?

  order.update!(paid: true)
  { success: true, transaction_id: result.id }
end
```

## Why This Is Good

- **Linear reading.** Each guard clause handles one error and returns. After all guards pass, the happy path runs with no nesting. You read top to bottom, not inside-out.
- **The happy path is at the natural indentation level.** No 5-level-deep nesting to find the actual business logic. The important code stands out visually.
- **Each guard is independent.** Adding a new validation (e.g., "order not already paid") means adding one `return unless` line, not wrapping another `if` around everything.
- **Easier to test.** Each guard clause corresponds to one test case. The tests mirror the guard order.

## When To Apply

- **Nested conditionals deeper than 2 levels.** If you're at 3+ levels of `if`, guards will flatten it.
- **Multiple preconditions before the main logic.** Auth checks, validation, null checks — these are guards.
- **The "else" branches are error handling.** If every `else` returns an error, those are guard clauses waiting to be extracted.
- **Case statements that switch on a type.** 3+ branches with distinct behavior → polymorphism. 2 branches → maybe keep the conditional.

## When NOT To Apply

- **Simple if/else with balanced branches.** `if premium? then charge(19) else charge(0) end` — both branches are the "main logic," not guards.
- **Two types that will never grow.** Boolean branching (`if active?`) rarely benefits from polymorphism.
- **The conditional is already clear at one level of nesting.** Don't refactor for refactoring's sake.

## Edge Cases

**Guard clauses in Rails controllers:**

```ruby
def update
  @order = current_user.orders.find_by(id: params[:id])
  return head :not_found unless @order
  return head :forbidden unless @order.editable?

  if @order.update(order_params)
    redirect_to @order
  else
    render :edit, status: :unprocessable_entity
  end
end
```

**Combining both refactorings:**
First flatten with guard clauses, then extract polymorphism for the remaining branching logic. Guard clauses handle preconditions; polymorphism handles type-based behavior.
