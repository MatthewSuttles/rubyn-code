# Code Quality: Value Objects

## Pattern

Replace primitive values (strings, integers, floats) that carry domain meaning with small, immutable objects that encapsulate the value AND its behavior. Value objects are equal by their attributes, not by identity.

```ruby
# Ruby 3.2+ Data class — the easiest way to create value objects
Money = Data.define(:amount_cents, :currency) do
  def initialize(amount_cents:, currency: "USD")
    super(amount_cents: Integer(amount_cents), currency: currency.to_s.upcase.freeze)
  end

  def to_f = amount_cents / 100.0
  def to_s = format("$%.2f %s", to_f, currency)
  def zero? = amount_cents.zero?

  def +(other)
    raise ArgumentError, "Currency mismatch: #{currency} vs #{other.currency}" unless currency == other.currency
    self.class.new(amount_cents: amount_cents + other.amount_cents, currency: currency)
  end

  def -(other)
    raise ArgumentError, "Currency mismatch" unless currency == other.currency
    self.class.new(amount_cents: amount_cents - other.amount_cents, currency: currency)
  end

  def *(factor)
    self.class.new(amount_cents: (amount_cents * factor).round, currency: currency)
  end

  def >(other) = amount_cents > other.amount_cents
  def <(other) = amount_cents < other.amount_cents
end

# Usage
price = Money.new(amount_cents: 19_99)
tax = price * 0.08
total = price + tax
puts total          # => "$21.59 USD"
puts total > price  # => true

# Equality by value, not identity
Money.new(amount_cents: 100) == Money.new(amount_cents: 100)  # => true
```

```ruby
# Email value object — validates and normalizes
Email = Data.define(:address) do
  EMAIL_REGEX = URI::MailTo::EMAIL_REGEXP

  def initialize(address:)
    normalized = address.to_s.downcase.strip
    raise ArgumentError, "Invalid email: #{address}" unless normalized.match?(EMAIL_REGEX)
    super(address: normalized.freeze)
  end

  def domain = address.split("@").last
  def local_part = address.split("@").first
  def to_s = address
  def personal? = !corporate?
  def corporate? = !domain.match?(/gmail|yahoo|hotmail|outlook/i)
end

email = Email.new(address: "  Alice@Example.COM  ")
email.address    # => "alice@example.com" (normalized)
email.domain     # => "example.com"
email.corporate? # => true
```

```ruby
# DateRange value object — common in reporting
DateRange = Data.define(:start_date, :end_date) do
  def initialize(start_date:, end_date:)
    start_date = Date.parse(start_date.to_s) unless start_date.is_a?(Date)
    end_date = Date.parse(end_date.to_s) unless end_date.is_a?(Date)
    raise ArgumentError, "start_date must be before end_date" if start_date > end_date
    super(start_date: start_date, end_date: end_date)
  end

  def days = (end_date - start_date).to_i
  def include?(date) = (start_date..end_date).cover?(date)
  def to_range = start_date..end_date
  def overlap?(other) = start_date <= other.end_date && end_date >= other.start_date
  def to_s = "#{start_date.iso8601} to #{end_date.iso8601}"

  def self.last_n_days(n) = new(start_date: n.days.ago.to_date, end_date: Date.today)
  def self.this_month = new(start_date: Date.today.beginning_of_month, end_date: Date.today)
end

period = DateRange.last_n_days(30)
orders = Order.where(created_at: period.to_range)
puts "#{period.days} days: #{orders.count} orders"
```

```ruby
# FileHash — wraps a checksum with comparison behavior
FileHash = Data.define(:digest) do
  def self.from_content(content)
    new(digest: Digest::SHA256.hexdigest(content))
  end

  def changed_from?(other)
    digest != other.digest
  end

  def to_s = digest[0..7]  # Short display
end

current = FileHash.from_content(file_content)
stored = FileHash.new(digest: embedding.file_hash)
reindex_file if current.changed_from?(stored)
```

## Why This Is Good

- **Impossible to have invalid values.** `Email.new(address: "not-an-email")` raises immediately. You can't pass an invalid email deeper into the system. Validation is at construction, not scattered across consumers.
- **Behavior lives with the data.** `money + other_money` handles currency matching. `email.domain` extracts the domain. Without value objects, this logic is duplicated wherever the primitive is used.
- **Self-documenting types.** `def charge(amount:)` accepting a `Money` is clearer than accepting an `Integer` (is it cents? dollars? what currency?). The type IS the documentation.
- **Immutable by default.** `Data.define` produces frozen objects. No accidental mutation, no defensive copying, no shared-state bugs.
- **Equality by value.** Two `Money` objects with the same amount and currency are equal. This makes them work correctly in Sets, as Hash keys, and with `==`.

## Anti-Pattern

Using primitives with scattered validation and formatting:

```ruby
class Order < ApplicationRecord
  validates :total, numericality: { greater_than: 0 }

  def formatted_total
    "$#{'%.2f' % (total / 100.0)}"
  end
end

class Invoice < ApplicationRecord
  validates :amount, numericality: { greater_than: 0 }

  def formatted_amount
    "$#{'%.2f' % (amount / 100.0)}"
  end
end

# In a service
def apply_discount(total_cents, discount_percentage)
  discount = (total_cents * discount_percentage / 100.0).round
  total_cents - discount
  # Wait — is total_cents in cents or dollars? The variable name says cents
  # but the discount_percentage calculation suggests... ?
end
```

## Why This Is Bad

- **Duplicated formatting.** `"$#{'%.2f' % (total / 100.0)}"` appears in Order, Invoice, and probably 5 other places. Change the format in one place, forget the others.
- **No currency safety.** Adding USD and EUR produces a meaningless number. With `Money`, it raises `ArgumentError`.
- **Ambiguous units.** Is `total` in cents or dollars? Is `discount_percentage` 10 or 0.10? Primitives don't communicate their units.
- **Validation scattered.** Every model independently validates numericality. With `Money`, the value object enforces validity at construction.

## When To Apply

- **Whenever a primitive carries domain meaning.** Money, email, phone number, URL, date range, coordinates, file hash, API key, color code.
- **When the same formatting/parsing appears in 2+ places.** That's behavior that belongs on a value object.
- **When you find yourself naming variables with units.** `amount_cents`, `distance_km`, `duration_seconds` — these are value objects screaming to be born.
- **When invalid values cause bugs.** If a negative amount, empty email, or swapped date range would cause downstream problems, make it impossible to construct.

## When NOT To Apply

- **Simple strings with no behavior.** A user's `first_name` is just a string — no formatting, validation, or arithmetic needed.
- **IDs and foreign keys.** These are database primitives. Wrapping `user_id` in a `UserId` value object is over-engineering.
- **Ephemeral values in a single method.** A loop counter or a temporary sum doesn't need a value object.

## Edge Cases

**Value objects in ActiveRecord:**
Store as a primitive in the DB, cast to a value object in Ruby:

```ruby
class Order < ApplicationRecord
  def total_money
    Money.new(amount_cents: total_cents, currency: currency)
  end

  def total_money=(money)
    self.total_cents = money.amount_cents
    self.currency = money.currency
  end
end

# Or use ActiveRecord::Attributes for automatic casting
class MoneyType < ActiveRecord::Type::Value
  def cast(value)
    case value
    when Money then value
    when Hash then Money.new(**value.symbolize_keys)
    when Integer then Money.new(amount_cents: value)
    end
  end

  def serialize(value)
    value&.amount_cents
  end
end
```

**Pre-Ruby 3.2 (no Data class):**
Use `Struct` with freeze:

```ruby
Money = Struct.new(:amount_cents, :currency, keyword_init: true) do
  def initialize(amount_cents:, currency: "USD")
    super
    freeze
  end
end
```
