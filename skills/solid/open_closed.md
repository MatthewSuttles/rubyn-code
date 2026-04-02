# SOLID: Open/Closed Principle (OCP)

## Pattern

Software entities should be open for extension but closed for modification. Add new behavior by writing new code (new classes, modules, or configurations) — not by editing existing, working code.

In Ruby, OCP is achieved through polymorphism, duck typing, dependency injection, and the Strategy pattern — not through inheritance hierarchies.

```ruby
# GOOD: New payment methods added without modifying existing code

# Each payment processor implements the same interface
class Payments::StripeProcessor
  def charge(amount_cents, payment_method_token)
    Stripe::Charge.create(
      amount: amount_cents,
      currency: "usd",
      source: payment_method_token
    )
    Result.new(success: true)
  rescue Stripe::CardError => e
    Result.new(success: false, error: e.message)
  end
end

class Payments::PaypalProcessor
  def charge(amount_cents, payment_method_token)
    PayPal::SDK::REST::Payment.new(
      intent: "sale",
      payer: { payment_method: "paypal" },
      transactions: [{ amount: { total: (amount_cents / 100.0).to_s, currency: "USD" } }]
    ).create
    Result.new(success: true)
  rescue PayPal::SDK::Core::Exceptions::ServerError => e
    Result.new(success: false, error: e.message)
  end
end

# Adding Braintree? Write a new class. Don't touch Stripe or PayPal.
class Payments::BraintreeProcessor
  def charge(amount_cents, payment_method_token)
    result = Braintree::Transaction.sale(
      amount: (amount_cents / 100.0).round(2),
      payment_method_nonce: payment_method_token
    )
    Result.new(success: result.success?, error: result.message)
  end
end

# The service accepts any processor — open for extension via injection
class Orders::ChargeService
  def initialize(processor:)
    @processor = processor
  end

  def call(order)
    result = @processor.charge(order.total_cents, order.payment_token)

    if result.success?
      order.update!(status: :paid, paid_at: Time.current)
    else
      order.update!(status: :payment_failed)
    end

    result
  end
end

# Usage — new processors slot in without touching ChargeService
processor = Payments::StripeProcessor.new
Orders::ChargeService.new(processor: processor).call(order)
```

Another common Ruby OCP pattern — registry/plugin architecture:

```ruby
# Notification channels — add new ones without modifying the dispatcher
class Notifications::Dispatcher
  REGISTRY = {}

  def self.register(channel_name, handler_class)
    REGISTRY[channel_name] = handler_class
  end

  def self.dispatch(user, message)
    user.notification_preferences.each do |channel|
      handler = REGISTRY[channel]
      handler&.new&.deliver(user, message)
    end
  end
end

# Each channel registers itself — no switch statements, no modification to Dispatcher
class Notifications::EmailHandler
  def deliver(user, message)
    NotificationMailer.notify(user, message).deliver_later
  end
end
Notifications::Dispatcher.register(:email, Notifications::EmailHandler)

class Notifications::SmsHandler
  def deliver(user, message)
    SmsClient.send(user.phone, message)
  end
end
Notifications::Dispatcher.register(:sms, Notifications::SmsHandler)

# Adding push notifications? New file, new class, one register call.
class Notifications::PushHandler
  def deliver(user, message)
    PushService.send(user.device_token, message)
  end
end
Notifications::Dispatcher.register(:push, Notifications::PushHandler)
```

## Why This Is Good

- **Existing code stays untouched.** Adding a new payment processor doesn't require editing `ChargeService`, `StripeProcessor`, or `PaypalProcessor`. Tested, deployed code remains stable.
- **Reduced regression risk.** When you don't modify existing code, you can't break existing behavior. The new `BraintreeProcessor` can only break Braintree payments.
- **Ruby duck typing makes this natural.** No need for explicit interfaces or abstract base classes. Any object that responds to `charge(amount_cents, token)` works as a processor. Ruby's flexibility makes OCP lightweight.
- **Dependency injection is the mechanism.** `ChargeService.new(processor: processor)` accepts any processor at runtime. The service doesn't know or care which processor it gets — it just calls `charge`.

## Anti-Pattern

A case/when statement that grows every time a new type is added:

```ruby
class Orders::ChargeService
  def call(order)
    case order.payment_method
    when "stripe"
      charge_with_stripe(order)
    when "paypal"
      charge_with_paypal(order)
    when "braintree"
      charge_with_braintree(order)
    when "apple_pay"
      charge_with_apple_pay(order)
    # Every new payment method adds another branch HERE
    end
  end

  private

  def charge_with_stripe(order)
    # 20 lines of Stripe-specific code
  end

  def charge_with_paypal(order)
    # 20 lines of PayPal-specific code
  end

  def charge_with_braintree(order)
    # 20 lines of Braintree-specific code
  end

  def charge_with_apple_pay(order)
    # 20 lines of Apple Pay-specific code
  end
end
```

## Why This Is Bad

- **Every new type modifies existing code.** Adding Apple Pay means opening `ChargeService` and adding a new `when` branch and a new private method. The class is modified, not extended.
- **Growing case statements.** With 10 payment methods, this class has 10 branches and 10 private methods. It's 200+ lines of unrelated payment logic in one file.
- **Impossible to test in isolation.** Testing Stripe logic means loading the entire `ChargeService` with all its payment method dependencies. You can't test one processor without the others being present.
- **Violates SRP too.** `ChargeService` now has 4 reasons to change — one for each payment provider's API changes.

## When To Apply

- **You see a `case` or `if/elsif` that switches on a type.** `case record.type`, `if method == :stripe`, `when "csv"` — these are branching on type, which is polymorphism waiting to happen.
- **You expect more variants in the future.** If you have 2 payment methods and expect 5, design for extension now. If you have 2 and will only ever have 2, a simple `if` is fine.
- **Multiple team members add different variants.** If one developer adds Stripe while another adds PayPal, separate classes prevent merge conflicts and enable parallel work.

## When NOT To Apply

- **Stable, finite branching.** A method that handles `success` and `failure` doesn't need polymorphism. Two branches that will never grow are fine as an `if/else`.
- **Don't create abstract factories for 2 classes.** OCP is about enabling future extension, not building frameworks. If you have 2 processors and no plans for a third, injecting a concrete processor is sufficient.
- **Rails conventions already handle this.** STI, enums with methods, and ActiveSupport::Concern are Rails' way of achieving OCP. Don't reinvent a plugin architecture when Rails patterns suffice.

## Edge Cases

**Ruby blocks as the ultimate OCP mechanism:**
Blocks let you inject behavior without any class:

```ruby
def process_items(items, &formatter)
  items.each { |item| puts formatter.call(item) }
end

process_items(orders) { |o| "#{o.reference}: $#{o.total}" }
process_items(orders) { |o| o.to_json }
```

**When the switch is on YOUR domain types (enums):**
Rails enums with methods on the model can be a pragmatic alternative to full polymorphism:

```ruby
class Order < ApplicationRecord
  enum :status, { pending: 0, confirmed: 1, shipped: 2 }

  def status_label
    { "pending" => "Awaiting Confirmation",
      "confirmed" => "Processing",
      "shipped" => "On Its Way" }[status]
  end
end
```

This is fine for display logic. For complex behavior that differs by status (different validations, different transitions, different side effects), use the State pattern instead.
