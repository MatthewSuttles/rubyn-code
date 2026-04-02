# Ruby: Pattern Matching

## Pattern

Ruby 3.x introduced structural pattern matching with `case/in`. It destructures arrays, hashes, and objects, binds variables, and replaces complex conditional chains with declarative matching. Use it for API response handling, parsing, and multi-branch logic on complex data.

### Basic Matching

```ruby
# Match on value
case status
in "pending"
  process_pending
in "shipped"
  process_shipped
in "delivered" | "completed"  # OR pattern
  mark_complete
in String => unknown_status   # Catch-all with binding
  Rails.logger.warn("Unknown status: #{unknown_status}")
end

# Match on type
case value
in Integer => n if n.positive?
  "Positive integer: #{n}"
in Float
  "A float"
in String
  "A string"
in nil
  "Nothing"
end
```

### Hash Destructuring

```ruby
# Parse API responses
response = { status: 200, body: { user: { name: "Alice", role: "admin", plan: "pro" } } }

case response
in { status: 200, body: { user: { role: "admin", name: String => name } } }
  puts "Admin user: #{name}"
in { status: 200, body: { user: { plan: "pro", name: String => name } } }
  puts "Pro user: #{name}"
in { status: 200, body: { user: { name: String => name } } }
  puts "Standard user: #{name}"
in { status: (400..499) => code }
  puts "Client error: #{code}"
in { status: (500..) => code }
  puts "Server error: #{code}"
end

# One-line destructuring with =>
response => { body: { user: { name: } } }
puts name  # => "Alice"

# Nested destructuring
webhook = { event: "order.shipped", data: { order_id: 42, tracking: "1Z999" } }
webhook => { event: /^order\.(.+)/ => event, data: { order_id: Integer => id } }
puts "Order #{id}: #{event}"
```

### Array Destructuring

```ruby
# Head and tail
case [1, 2, 3, 4, 5]
in [first, *rest]
  puts "First: #{first}, rest: #{rest}"
  # First: 1, rest: [2, 3, 4, 5]
end

# Find pattern — match an element anywhere in the array
case ["info", "warning", "error: disk full", "info"]
in [*, /^error: (.+)/ => error_msg, *]
  puts "Found error: #{error_msg}"
end

# Fixed structure
case [200, "OK", { content_type: "application/json" }]
in [200, String => msg, Hash => headers]
  puts "Success: #{msg}"
in [(400..499) => code, String => msg, _]
  puts "Client error #{code}: #{msg}"
end
```

### Pin Operator (Match Against Existing Variables)

```ruby
expected_status = "shipped"

case order
in { status: ^expected_status }  # ^ pins the variable — matches its VALUE, not a new binding
  puts "Order is shipped!"
in { status: String => actual }
  puts "Expected #{expected_status}, got #{actual}"
end

# Without ^, `expected_status` would be a new binding, not a comparison
```

### Guard Conditions

```ruby
case order
in { total: Integer => amount } if amount > 100_00
  apply_free_shipping(order)
in { total: Integer => amount } if amount > 50_00
  apply_discount_shipping(order)
in { total: Integer }
  apply_standard_shipping(order)
end
```

### Practical Rails Uses

```ruby
# Webhook handler — clean multi-type dispatch
class Webhooks::StripeHandler
  def call(event)
    case event
    in { type: "checkout.session.completed", data: { object: { customer: String => customer_id, amount_total: Integer => amount } } }
      process_checkout(customer_id, amount)
    in { type: "invoice.payment_failed", data: { object: { customer: String => customer_id } } }
      handle_payment_failure(customer_id)
    in { type: /^customer\.subscription\./, data: { object: { id: String => sub_id, status: String => status } } }
      update_subscription(sub_id, status)
    in { type: String => type }
      Rails.logger.info("Unhandled webhook: #{type}")
    end
  end
end

# Service result handling
case Orders::CreateService.call(params, user)
in { success: true, order: Order => order }
  redirect_to order
in { success: false, error: String => message }
  flash.now[:alert] = message
  render :new, status: :unprocessable_entity
end

# Config validation at boot
case Rails.application.credentials.config
in { anthropic: { api_key: String }, database: { url: String } }
  # All required config present
in { anthropic: nil | { api_key: nil } }
  raise "Missing Anthropic API key in credentials"
in { database: nil | { url: nil } }
  raise "Missing database URL in credentials"
end
```

## Why This Is Good

- **Declarative over imperative.** `case/in` says WHAT you're looking for. Nested `if/elsif` chains say HOW to check.
- **Destructuring binds variables inline.** `{ user: { name: String => name } }` both validates the structure AND extracts the value in one expression.
- **Exhaustive matching catches missing cases.** If no pattern matches, Ruby raises `NoMatchingPatternError`. This catches unhandled types at runtime instead of silently returning nil.
- **Readable webhook/API handling.** Stripe webhooks have deeply nested JSON. Pattern matching handles them in 3 lines instead of 15.
- **Pin operator enables dynamic matching.** `^expected_value` matches against a variable's value without rebinding it.

## When To Apply

- **Webhook handlers** — matching on event type and extracting nested data from JSON payloads.
- **API response parsing** — matching on status codes and body structure.
- **Multi-type dispatch** — when a method receives different shapes of input and must handle each differently.
- **Config validation** — asserting required structure exists at boot time.
- **Result object handling** — matching on success/failure with different payloads.

## When NOT To Apply

- **Simple equality checks.** `case status when "pending"` is clearer than `case status in "pending"` for flat value matching. Use `case/when` for simple equality, `case/in` for structural matching.
- **Ruby < 3.0 projects.** Pattern matching is Ruby 3+ only. Check the project's `.ruby-version`.
- **Performance-critical hot paths.** Pattern matching is slightly slower than direct hash access. For code that runs millions of times, use `dig` / `fetch` directly.
- **When the team isn't familiar.** Pattern matching is powerful but unfamiliar to many Rubyists. If the team hasn't adopted it, don't introduce it in one file.
