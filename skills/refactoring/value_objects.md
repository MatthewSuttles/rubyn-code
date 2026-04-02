# Refactoring: Replace Primitive with Value Object

## Pattern

When primitives (strings, integers, floats) carry domain meaning, replace them with value objects that encapsulate the value, its validation, and its behavior. This eliminates scattered validation logic and gives you a natural place for formatting, comparison, and conversion methods.

```ruby
# BEFORE: Money as cents integer, scattered formatting
class Order < ApplicationRecord
  def formatted_total
    "$#{format('%.2f', total / 100.0)}"
  end

  def total_with_tax
    total + (total * 0.08).round
  end
end

class Invoice
  def formatted_amount
    "$#{format('%.2f', amount_cents / 100.0)}"  # Same logic, different variable name
  end
end

# AFTER: Money value object
class Money
  include Comparable
  attr_reader :cents, :currency

  def initialize(cents, currency = "USD")
    @cents = Integer(cents)
    @currency = currency.to_s.upcase.freeze
    freeze
  end

  def self.from_dollars(dollars, currency = "USD")
    new((Float(dollars) * 100).round, currency)
  end

  def to_f
    cents / 100.0
  end

  def to_s
    "$#{format('%.2f', to_f)}"
  end

  def +(other)
    assert_same_currency!(other)
    self.class.new(cents + other.cents, currency)
  end

  def -(other)
    assert_same_currency!(other)
    self.class.new(cents - other.cents, currency)
  end

  def *(multiplier)
    self.class.new((cents * multiplier).round, currency)
  end

  def <=>(other)
    return nil unless other.is_a?(Money) && currency == other.currency
    cents <=> other.cents
  end

  def zero?
    cents.zero?
  end

  def positive?
    cents.positive?
  end

  private

  def assert_same_currency!(other)
    raise ArgumentError, "Currency mismatch: #{currency} vs #{other.currency}" unless currency == other.currency
  end
end

# Usage — clean, safe, reusable
price = Money.new(19_99)
tax = price * 0.08
total = price + tax
total.to_s  # => "$21.59"
total > Money.new(20_00)  # => true
```

```ruby
# BEFORE: Email as a string, validated in multiple places
class User < ApplicationRecord
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  before_validation { self.email = email&.downcase&.strip }
end

class Invite < ApplicationRecord
  validates :recipient_email, format: { with: URI::MailTo::EMAIL_REGEXP }
  before_validation { self.recipient_email = recipient_email&.downcase&.strip }
end

# AFTER: Email value object
class Email
  REGEXP = URI::MailTo::EMAIL_REGEXP

  attr_reader :address

  def initialize(raw)
    @address = raw.to_s.downcase.strip.freeze
    raise ArgumentError, "Invalid email: #{raw}" unless valid?
    freeze
  end

  def valid?
    REGEXP.match?(@address)
  end

  def domain
    @address.split("@").last
  end

  def to_s = @address
  def ==(other) = other.is_a?(Email) && address == other.address
  alias_method :eql?, :==
  def hash = address.hash
end

# Usage
email = Email.new("  Alice@Example.COM  ")
email.to_s     # => "alice@example.com"
email.domain   # => "example.com"
```

# Refactoring: Introduce Parameter Object

## Pattern

When the same group of parameters is passed together to multiple methods, bundle them into an object.

```ruby
# BEFORE: Same 3 params passed everywhere
def search_orders(start_date, end_date, status)
  Order.where(created_at: start_date..end_date, status: status)
end

def export_orders(start_date, end_date, status, format)
  orders = search_orders(start_date, end_date, status)
  # ...
end

def count_orders(start_date, end_date, status)
  search_orders(start_date, end_date, status).count
end
```

```ruby
# AFTER: Parameter object bundles related params
class DateRange
  attr_reader :start_date, :end_date

  def initialize(start_date:, end_date:)
    @start_date = start_date.to_date
    @end_date = end_date.to_date
    raise ArgumentError, "start must be before end" if @start_date > @end_date
    freeze
  end

  def to_range
    start_date..end_date
  end

  def days
    (end_date - start_date).to_i
  end

  def include?(date)
    to_range.include?(date)
  end
end

OrderFilter = Data.define(:date_range, :status) do
  def to_scope(base = Order.all)
    scope = base.where(created_at: date_range.to_range)
    scope = scope.where(status: status) if status.present?
    scope
  end
end

# Usage — clean, validated, reusable
filter = OrderFilter.new(
  date_range: DateRange.new(start_date: 30.days.ago, end_date: Date.today),
  status: "pending"
)

orders = filter.to_scope
count = filter.to_scope.count
export = Orders::Exporter.call(filter.to_scope, format: :csv)
```

## Why This Is Good

- **Validation in one place.** `Money.new(-100)` is valid (a refund). `Email.new("not-valid")` raises immediately. No scattered regex checks.
- **Behavior on the object.** `money + other_money` handles currency matching. `email.domain` extracts the domain. Primitives have none of this.
- **Type safety through construction.** If a method accepts a `Money`, you know it's a valid integer of cents with a currency. If it accepts an `Integer`, it could be anything.
- **Eliminates duplicated formatting.** `money.to_s` always returns `"$19.99"`. No more `"$#{format('%.2f', cents / 100.0)}"` repeated in 12 views.
- **Comparable, hashable, freezable.** Value objects work as hash keys, in Sets, and in sorted collections. Primitives require manual comparison logic.

## When To Apply

- **The same primitive has validation logic in 2+ places.** Email format, money formatting, phone number parsing — extract once.
- **The same group of parameters travels together.** `start_date, end_date` → `DateRange`. `street, city, state, zip` → `Address`.
- **Arithmetic or comparison on the primitive.** If you add, subtract, or compare cents in 5 places, a Money object centralizes the logic.
- **A method has 4+ parameters.** Look for parameter groups to bundle.

## When NOT To Apply

- **A string that's just a string.** A user's `name` field doesn't need a `Name` value object unless you need parsing (first/last) or validation logic.
- **One-off usage.** If a date range is used in exactly one query, inlining `where(created_at: start..end)` is fine.
- **Don't create value objects for configuration.** `timeout: 30` doesn't need a `Timeout` value object.

## Edge Cases

**Value objects as ActiveRecord attributes:**
Use `composed_of` or custom attribute types:

```ruby
class Order < ApplicationRecord
  composed_of :total_money,
    class_name: "Money",
    mapping: [%w[total_cents cents], %w[currency currency]]
end

order.total_money  # => Money(1999, "USD")
order.total_money.to_s  # => "$19.99"
```

**Ruby 3.2+ `Data` class for simple value objects:**

```ruby
Point = Data.define(:x, :y)
point = Point.new(x: 1, y: 2)
point.x  # => 1
point.frozen?  # => true
```

`Data.define` is perfect for simple value objects that don't need custom behavior beyond attribute access.
