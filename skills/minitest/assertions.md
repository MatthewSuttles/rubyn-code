# Minitest: Assertions

## Pattern

Minitest assertions are simple methods: `assert_*` for positive checks, `refute_*` for negative checks. Choose the most specific assertion for the clearest failure messages.

### Core Assertions

```ruby
class OrderTest < ActiveSupport::TestCase
  # Equality
  assert_equal 100, order.total                    # Expected vs actual
  assert_equal "pending", order.status
  refute_equal 0, order.total                      # Not equal

  # Truthiness
  assert order.valid?                              # Truthy
  refute order.shipped?                            # Falsy
  assert_nil order.cancelled_at                    # Exactly nil
  refute_nil order.reference                       # Not nil

  # Predicate methods (reads better)
  assert_predicate order, :valid?                  # Same as assert order.valid?
  assert_predicate order, :pending?
  refute_predicate order, :shipped?

  # Includes
  assert_includes Order.recent, order              # Collection includes item
  refute_includes Order.recent, old_order

  # Type checking
  assert_instance_of Order, result                 # Exact class
  assert_kind_of ApplicationRecord, result         # Class or subclass

  # Pattern matching
  assert_match /ORD-\d{6}/, order.reference        # Regex match
  refute_match /INVALID/, order.reference

  # Numeric
  assert_in_delta 10.5, calculated_tax, 0.01       # Float comparison with tolerance
  assert_operator order.total, :>, 0               # order.total > 0

  # Exceptions
  assert_raises ActiveRecord::RecordInvalid do
    Order.create!(shipping_address: nil)
  end

  error = assert_raises ArgumentError do
    Money.new("not a number")
  end
  assert_match /invalid/, error.message

  # Empty / present
  assert_empty order.line_items                     # .empty? is true
  refute_empty order.errors.full_messages

  # Response assertions (Rails integration tests)
  assert_response :success                          # 200
  assert_response :redirect                         # 3xx
  assert_response :not_found                        # 404
  assert_response :unprocessable_entity             # 422
  assert_redirected_to order_path(order)

  # Difference assertions (Rails)
  assert_difference "Order.count", 1 do
    post orders_path, params: { order: valid_params }
  end

  assert_no_difference "Order.count" do
    post orders_path, params: { order: invalid_params }
  end

  assert_difference -> { user.reload.credit_balance }, -10 do
    Credits::DeductionService.call(user, 10)
  end

  # Multiple differences at once
  assert_difference ["Order.count", "LineItem.count"], 1 do
    post orders_path, params: { order: valid_params }
  end

  # Enqueued jobs
  assert_enqueued_with(job: OrderConfirmationJob, args: [order.id]) do
    Orders::CreateService.call(params, user)
  end

  assert_enqueued_jobs 1 do
    order.confirm!
  end

  assert_no_enqueued_jobs do
    order.update!(notes: "updated")
  end

  # Emails
  assert_emails 1 do
    Orders::CreateService.call(params, user)
  end

  assert_no_emails do
    order.update!(shipping_address: "new address")
  end
end
```

### Custom Assertions

```ruby
# test/support/custom_assertions.rb
module CustomAssertions
  def assert_valid(record, msg = nil)
    assert record.valid?, msg || "Expected #{record.class} to be valid, but got errors: #{record.errors.full_messages.join(', ')}"
  end

  def assert_invalid(record, *attributes)
    refute record.valid?, "Expected #{record.class} to be invalid"
    attributes.each do |attr|
      assert record.errors[attr].any?, "Expected errors on #{attr}, but found none"
    end
  end

  def assert_json_response(*keys)
    json = JSON.parse(response.body)
    keys.each do |key|
      assert json.key?(key.to_s), "Expected JSON to include key '#{key}'"
    end
  end
end

# Include in test_helper.rb
class ActiveSupport::TestCase
  include CustomAssertions
end

# Usage
test "order is valid with all required fields" do
  order = Order.new(user: @user, shipping_address: "123 Main")
  assert_valid order
end

test "order is invalid without address" do
  order = Order.new(user: @user)
  assert_invalid order, :shipping_address
end
```

## Why This Is Good

- **Specific assertions give specific failure messages.** `assert_equal 100, order.total` fails with `Expected: 100, Actual: 0`. A bare `assert order.total == 100` fails with `Expected false to be truthy` — useless.
- **`assert_difference` is concise and safe.** It captures the before value, runs the block, then checks the after value. No manual before/after variables.
- **`assert_raises` captures the exception.** You can assert on the exception message, not just that it was raised.
- **Custom assertions DRY up common patterns.** `assert_invalid(order, :email)` is clearer than 3 lines of refute + assert_includes.

## Anti-Pattern

Using `assert` for everything:

```ruby
# BAD: Bare assert gives terrible failure messages
assert order.total == 100           # "Expected false to be truthy"
assert order.errors.any?            # "Expected false to be truthy"
assert Order.recent.include?(order) # "Expected false to be truthy"

# GOOD: Specific assertions
assert_equal 100, order.total       # "Expected: 100, Actual: 0"
refute_empty order.errors           # "Expected [] to not be empty"
assert_includes Order.recent, order # "Expected [...] to include #<Order ...>"
```

## Assertion Cheat Sheet

| Want to check... | Use |
|---|---|
| Two values are equal | `assert_equal expected, actual` |
| Value is nil | `assert_nil value` |
| Value is not nil | `refute_nil value` |
| Boolean predicate | `assert_predicate obj, :method?` |
| Collection contains item | `assert_includes collection, item` |
| String matches pattern | `assert_match /regex/, string` |
| Code raises exception | `assert_raises(ErrorClass) { code }` |
| DB record count changes | `assert_difference "Model.count", N { code }` |
| Floats are close enough | `assert_in_delta expected, actual, delta` |
| Object is correct type | `assert_instance_of Klass, obj` |
| Collection is empty | `assert_empty collection` |
| Custom condition failed | `assert condition, "descriptive message"` |
