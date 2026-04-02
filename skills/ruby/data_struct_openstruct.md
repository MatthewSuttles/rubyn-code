# Ruby: Data, Struct, and OpenStruct

## Pattern

Ruby provides three built-in ways to create simple data-holding classes. Choose the right one based on mutability needs and Ruby version.

### Data (Ruby 3.2+) — Immutable Value Objects

```ruby
# Data.define creates a frozen, immutable value class
Point = Data.define(:x, :y)
Money = Data.define(:cents, :currency)
DateRange = Data.define(:start_date, :end_date)

# Creation
point = Point.new(x: 10, y: 20)
price = Money.new(cents: 19_99, currency: "USD")

# Immutable — frozen by default
point.x        # => 10
point.frozen?  # => true
point.x = 5   # => FrozenError

# Equality by value
Point.new(x: 1, y: 2) == Point.new(x: 1, y: 2)  # => true

# Pattern matching
case price
in Money[cents: (0..99), currency: "USD"]
  "Under a dollar"
in Money[cents: (100..), currency: "USD"]
  "A dollar or more"
end

# Add behavior with a block
Money = Data.define(:cents, :currency) do
  def to_s
    "$#{format('%.2f', cents / 100.0)}"
  end

  def +(other)
    raise ArgumentError, "Currency mismatch" unless currency == other.currency
    self.class.new(cents: cents + other.cents, currency: currency)
  end

  def self.zero(currency = "USD")
    new(cents: 0, currency: currency)
  end
end

price = Money.new(cents: 10_00, currency: "USD")
tax = Money.new(cents: 80, currency: "USD")
total = price + tax
total.to_s  # => "$10.80"
```

### Struct — Mutable Data Containers

```ruby
# Struct creates a mutable class with attribute accessors
OrderSummary = Struct.new(:reference, :total, :status, keyword_init: true)

summary = OrderSummary.new(reference: "ORD-001", total: 50_00, status: "pending")
summary.reference  # => "ORD-001"
summary.status = "shipped"  # Mutable — can change

# Struct supports Enumerable
summary.to_a       # => ["ORD-001", 50_00, "shipped"]
summary.to_h       # => { reference: "ORD-001", total: 50_00, status: "shipped" }

# Add methods
Result = Struct.new(:success, :value, :error, keyword_init: true) do
  def success?
    success == true
  end

  def failure?
    !success?
  end
end

result = Result.new(success: true, value: order, error: nil)
result.success?  # => true
```

### OpenStruct — Dynamic Attributes (Use Sparingly)

```ruby
# OpenStruct allows any attribute — no predefined structure
config = OpenStruct.new(api_key: "sk-123", timeout: 30)
config.api_key    # => "sk-123"
config.new_field = "added dynamically"  # Any attribute, any time
config.new_field  # => "added dynamically"

# OpenStruct is SLOW — uses method_missing internally
# ~10x slower than Struct for attribute access
# ~100x slower than a plain class
```

## Decision Tree

```
Do you need a simple data container?
├── Is the data immutable (value object)?
│   ├── Ruby 3.2+? → Data.define
│   └── Ruby < 3.2? → Struct.new with .freeze
├── Is the data mutable?
│   └── Struct.new (keyword_init: true)
├── Are attributes dynamic/unknown at design time?
│   └── OpenStruct (but consider a Hash instead)
└── Does the object need complex behavior?
    └── Write a full class
```

## When To Apply

- **`Data.define`** for value objects: Money, Email, Coordinates, API responses, Result types. Anywhere immutability and value equality matter.
- **`Struct`** for simple data transfer objects: search results, service return types, configuration that's built step by step.
- **OpenStruct** for quick prototyping only. Replace with Struct or Data before code review.

## When NOT To Apply

- **ActiveRecord models.** They have their own attribute system. Don't wrap them in Struct/Data.
- **Complex domain objects.** If the object has 5+ methods of behavior (not just accessors), write a class.
- **Performance-critical paths.** OpenStruct is slow. In hot loops, use Struct or plain classes.
- **OpenStruct in production code.** Its dynamic nature makes typos silent (`config.api_ky = "..."` creates a new attribute instead of raising). Struct catches this at construction time.

## Edge Cases

**Struct as a base class:**
```ruby
class User < Struct.new(:name, :email, keyword_init: true)
  def greeting
    "Hello, #{name}!"
  end
end
```
This works but is considered unusual. Prefer `Data.define` with a block or a plain class.

**Freezing a Struct for immutability (pre-Ruby 3.2):**
```ruby
Config = Struct.new(:api_key, :timeout, keyword_init: true)
config = Config.new(api_key: "sk-123", timeout: 30).freeze
config.api_key = "new"  # => FrozenError
```

**Nested Data objects:**
```ruby
Address = Data.define(:street, :city, :state, :zip)
Customer = Data.define(:name, :email, :address)

customer = Customer.new(
  name: "Alice",
  email: "alice@example.com",
  address: Address.new(street: "123 Main", city: "Austin", state: "TX", zip: "78701")
)
customer.address.city  # => "Austin"
```
