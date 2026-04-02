# Ruby: Class Design

## Pattern

Design classes with a single responsibility, a clear public interface, and minimal exposure of internal state. Use `attr_reader` by default, only use `attr_accessor` when mutation is intentional, and freeze objects when immutability is desirable.

```ruby
# GOOD: Clear responsibility, minimal interface, protected internals
class Money
  attr_reader :amount_cents, :currency

  def initialize(amount_cents, currency = "USD")
    @amount_cents = Integer(amount_cents)
    @currency = currency.to_s.upcase.freeze
    freeze
  end

  def to_f
    amount_cents / 100.0
  end

  def to_s
    format("%.2f %s", to_f, currency)
  end

  def +(other)
    raise ArgumentError, "Currency mismatch" unless currency == other.currency

    self.class.new(amount_cents + other.amount_cents, currency)
  end

  def >(other)
    raise ArgumentError, "Currency mismatch" unless currency == other.currency

    amount_cents > other.amount_cents
  end

  def ==(other)
    other.is_a?(self.class) &&
      amount_cents == other.amount_cents &&
      currency == other.currency
  end
  alias_method :eql?, :==

  def hash
    [amount_cents, currency].hash
  end
end
```

Constructor patterns:

```ruby
# Named constructor for clarity
class Order
  def self.from_cart(cart, user)
    new(
      user: user,
      line_items: cart.items.map { |item| LineItem.new(product: item.product, quantity: item.quantity) },
      shipping_address: user.default_address
    )
  end

  def initialize(user:, line_items:, shipping_address:)
    @user = user
    @line_items = line_items
    @shipping_address = shipping_address
  end
end

# Usage reads like English
order = Order.from_cart(cart, current_user)
```

## Why This Is Good

- **`attr_reader` protects state.** External code can read `money.amount_cents` but can't set it. State changes only happen through explicit methods with names that communicate intent.
- **`freeze` enforces immutability.** A frozen Money object can't be accidentally mutated. Operations like `+` return new instances. This eliminates an entire class of bugs where shared references are modified in place.
- **Named constructors improve readability.** `Order.from_cart(cart, user)` is clearer than `Order.new(user: user, line_items: cart.items.map { ... })`. The constructor name describes the context.
- **`==` and `hash` make objects work in collections.** Two Money objects with the same amount and currency are equal, can be used as hash keys, and work with `uniq`, `include?`, and Set operations.
- **Keyword arguments in constructors.** `new(user:, line_items:, shipping_address:)` is self-documenting. You can't accidentally swap argument order.

## Anti-Pattern

Classes with `attr_accessor` on everything, no encapsulation, and public state mutation:

```ruby
class Order
  attr_accessor :user, :items, :status, :total, :tax, :discount,
                :shipping_address, :billing_address, :notes,
                :created_at, :updated_at

  def initialize
    @items = []
    @status = "pending"
  end
end

# External code reaches in and mutates freely
order = Order.new
order.user = current_user
order.items << line_item
order.items << another_item
order.total = order.items.sum(&:price)
order.tax = order.total * 0.08
order.total = order.total + order.tax
order.status = "confirmed"
```

## Why This Is Bad

- **No encapsulation.** Any code anywhere can set `order.status = "shipped"` without any validation or side-effect management. The object can't protect its own invariants.
- **Scattered logic.** Total calculation happens outside the class. Tax calculation happens outside. The object is a passive data bag that external code manipulates.
- **Impossible to refactor.** Renaming `@total` to `@amount` requires finding every `order.total =` call across the entire codebase. With a method, you change one place.
- **No constructor contract.** `Order.new` creates an incomplete, invalid object. The caller must remember to set user, items, total, and tax in the correct order. Missing any step produces a broken object silently.

## When To Apply

- **Every class you write.** Single responsibility and minimal public interface aren't optional patterns — they're baseline class design.
- **Value objects** (Money, DateRange, Coordinate, EmailAddress) should always be frozen and immutable.
- **Service objects and domain objects** should use `attr_reader` for dependencies and `private` for implementation details.
- **Use keyword arguments** when a constructor has more than 2 parameters, or when the parameters are the same type (two strings, two integers) and could be confused.

## When NOT To Apply

- **ActiveRecord models** follow their own conventions. `attr_accessor` for virtual attributes is normal in Rails models. Don't fight the framework.
- **Structs and Data objects** use `attr_reader` automatically. You don't need to define them manually.
- **Configuration objects** that are built incrementally (builder pattern) may need `attr_writer` during construction, then frozen after.

## Edge Cases

**You need a mutable object but want controlled mutation:**
Use explicit setter methods with validation instead of `attr_accessor`:

```ruby
class Account
  attr_reader :balance

  def deposit(amount)
    raise ArgumentError, "Amount must be positive" unless amount > 0
    @balance += amount
  end

  def withdraw(amount)
    raise InsufficientFunds if amount > @balance
    @balance -= amount
  end
end
```

**Too many constructor arguments (more than 4-5):**
Consider a parameter object, a builder, or breaking the class into smaller collaborators. A constructor with 8 keyword arguments is a sign the class has too many responsibilities.

**Inheritance vs composition:**
Default to composition. If you're inheriting just to share code, use a module instead. Inherit only when there's a genuine "is-a" relationship and you want polymorphism.
