# Code Quality: YAGNI — You Ain't Gonna Need It

## Core Principle

Don't build it until you need it. Every line of code is a liability — it must be tested, maintained, and understood. Code that exists "in case we need it later" is code that costs you now and may never pay off.

## The Three Questions

Before adding abstraction, ask:

1. **Do I need this right now, or might I need it later?** If "later," don't build it.
2. **Am I building for the problem I have, or the problem I imagine?** Solve the real problem.
3. **What's the cost of adding this later when I actually need it?** Usually low. Build then.

## Premature Abstraction

```ruby
# YAGNI VIOLATION: Building a plugin system for 1 payment provider
class PaymentProcessorFactory
  REGISTRY = {}

  def self.register(name, klass)
    REGISTRY[name] = klass
  end

  def self.build(name, **config)
    klass = REGISTRY.fetch(name)
    klass.new(**config)
  end
end

class PaymentProcessor
  def charge(amount, token) = raise NotImplementedError
  def refund(transaction_id, amount) = raise NotImplementedError
  def void(transaction_id) = raise NotImplementedError
end

class StripeProcessor < PaymentProcessor
  def charge(amount, token)
    # Stripe-specific code
  end

  def refund(transaction_id, amount)
    # Stripe-specific code
  end

  def void(transaction_id)
    # Stripe-specific code
  end
end

PaymentProcessorFactory.register(:stripe, StripeProcessor)
```

You have ONE payment provider. The factory, the abstract base class, and the registration mechanism add ~40 lines of code that provide zero value today. When you actually need a second provider (if you ever do), adding the abstraction takes 30 minutes.

```ruby
# RIGHT-SIZED: Direct implementation for the one provider you have
class Payments::StripeService
  def charge(amount_cents, token)
    charge = Stripe::Charge.create(amount: amount_cents, currency: "usd", source: token)
    Result.new(success: true, transaction_id: charge.id)
  rescue Stripe::CardError => e
    Result.new(success: false, error: e.message)
  end

  def refund(charge_id, amount_cents)
    Stripe::Refund.create(charge: charge_id, amount: amount_cents)
    Result.new(success: true)
  rescue Stripe::InvalidRequestError => e
    Result.new(success: false, error: e.message)
  end
end
```

## Speculative Generality Examples

```ruby
# YAGNI: Config class for 2 settings
class Configuration
  include Singleton
  attr_accessor :settings

  def initialize
    @settings = {}
  end

  def get(key, default: nil)
    settings.dig(*key.to_s.split(".")) || default
  end

  def set(key, value)
    keys = key.to_s.split(".")
    hash = keys[0..-2].reduce(settings) { |h, k| h[k] ||= {} }
    hash[keys.last] = value
  end
end

# You only have: API key and model name. Just use ENV.
# ENV["ANTHROPIC_API_KEY"] and ENV["MODEL_NAME"] are simpler.
```

```ruby
# YAGNI: Abstract base class with one subclass
class BaseExporter
  def export(data)
    header + body(data) + footer
  end

  def header = raise NotImplementedError
  def body(data) = raise NotImplementedError
  def footer = raise NotImplementedError
end

class CsvExporter < BaseExporter
  def header = "id,name,total\n"
  def body(data) = data.map { |r| "#{r.id},#{r.name},#{r.total}" }.join("\n")
  def footer = ""
end

# One exporter doesn't need a base class. Just write CsvExporter directly.
# When you need PdfExporter, THEN extract the common interface.
```

## The Rule of Three

Don't abstract until you have three concrete examples:
1. **First time:** Just write the code.
2. **Second time:** Notice the duplication but tolerate it. Maybe add a comment "similar to X."
3. **Third time:** Now extract. You have three examples to inform the right abstraction.

```ruby
# First time: inline
class OrdersController
  def export
    csv = orders.map { |o| [o.reference, o.total].join(",") }.join("\n")
    send_data csv, filename: "orders.csv"
  end
end

# Second time: notice similarity, tolerate it
class InvoicesController
  def export
    csv = invoices.map { |i| [i.number, i.amount].join(",") }.join("\n")
    send_data csv, filename: "invoices.csv"
  end
end

# Third time: NOW extract
class CsvExporter
  def self.call(records, columns:, filename:)
    csv = records.map { |r| columns.map { |c| r.public_send(c) }.join(",") }.join("\n")
    { data: csv, filename: filename }
  end
end
```

## When YAGNI Doesn't Apply

- **Known requirements.** If the spec says "support Stripe and PayPal at launch," build the abstraction. That's not speculative — it's a stated requirement.
- **Architecture boundaries.** Even with one provider, wrapping external APIs behind an adapter is good practice. The adapter isn't speculative — it isolates you from API changes.
- **Security and data integrity.** Don't skip input validation because "we'll add it later." Security isn't optional.
- **Testing infrastructure.** Investing in test helpers, factories, and shared examples pays off immediately — not speculatively.

## The Cost of Abstraction

Every abstraction has a cost:
- **Indirection:** Readers must navigate to another file to understand behavior.
- **Maintenance:** The abstract interface must be kept in sync with all implementations.
- **Constraint:** Future implementations are shaped by the abstraction, which was designed without knowledge of their needs.

Premature abstraction is worse than no abstraction because it constrains future design based on incomplete information. The right abstraction, built with knowledge of 3+ concrete cases, enables extension. The wrong abstraction, built speculatively, requires fighting against it.

## Practical Test

Ask: "If I delete this abstraction and inline the code, does anything get worse?" If no — the abstraction isn't earning its keep. Delete it.
