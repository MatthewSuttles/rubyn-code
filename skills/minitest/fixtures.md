# Minitest: Fixtures

## Pattern

Rails fixtures are YAML files that define test data loaded once at suite start, wrapped in database transactions. They're fast, predictable, and the Minitest default. Use them as the primary test data strategy; reach for factories only when fixtures can't express what you need.

```yaml
# test/fixtures/users.yml
alice:
  email: alice@example.com
  name: Alice Johnson
  role: user
  plan: pro
  password_digest: <%= BCrypt::Password.create("password") %>

bob:
  email: bob@example.com
  name: Bob Smith
  role: user
  plan: free
  password_digest: <%= BCrypt::Password.create("password") %>

admin:
  email: admin@example.com
  name: Admin User
  role: admin
  plan: pro
  password_digest: <%= BCrypt::Password.create("password") %>
```

```yaml
# test/fixtures/orders.yml
pending_order:
  user: alice
  reference: ORD-000001
  shipping_address: 123 Main St
  status: pending
  total: 50_00

shipped_order:
  user: alice
  reference: ORD-000002
  shipping_address: 123 Main St
  status: shipped
  total: 100_00
  shipped_at: <%= 2.days.ago.to_fs(:db) %>

bobs_order:
  user: bob
  reference: ORD-000003
  shipping_address: 456 Oak Ave
  status: pending
  total: 25_00
```

```yaml
# test/fixtures/products.yml
widget:
  name: Widget
  price: 10_00
  stock: 100
  sku: WDG-001

gadget:
  name: Gadget
  price: 25_00
  stock: 50
  sku: GDG-001
```

Using fixtures in tests:

```ruby
class OrderTest < ActiveSupport::TestCase
  test "scopes orders to user" do
    alice_orders = Order.where(user: users(:alice))

    assert_includes alice_orders, orders(:pending_order)
    assert_includes alice_orders, orders(:shipped_order)
    refute_includes alice_orders, orders(:bobs_order)
  end

  test ".pending returns only pending orders" do
    pending = Order.pending

    assert_includes pending, orders(:pending_order)
    assert_includes pending, orders(:bobs_order)
    refute_includes pending, orders(:shipped_order)
  end

  test "total is positive" do
    assert_operator orders(:pending_order).total, :>, 0
  end
end
```

```ruby
# Integration test with fixtures
class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:alice)
  end

  test "index shows only current user's orders" do
    get orders_path

    assert_response :success
    assert_match orders(:pending_order).reference, response.body
    assert_no_match orders(:bobs_order).reference, response.body
  end

  test "create with valid params" do
    assert_difference "Order.count", 1 do
      post orders_path, params: {
        order: { shipping_address: "789 Elm St", product_id: products(:widget).id, quantity: 1 }
      }
    end

    assert_redirected_to Order.last
  end

  test "create with invalid params does not create order" do
    assert_no_difference "Order.count" do
      post orders_path, params: { order: { shipping_address: "" } }
    end

    assert_response :unprocessable_entity
  end
end
```

## Why This Is Good

- **Loaded once per suite.** Fixtures are inserted into the database once before all tests run, then wrapped in transactions. Each test rolls back to the same state. Zero per-test INSERT cost.
- **Predictable IDs.** `users(:alice).id` is the same every run. This makes debugging repeatable and assertions stable.
- **Relationships via labels.** `user: alice` in the order fixture automatically resolves to `users(:alice).id`. No manual ID management.
- **ERB support.** `<%= BCrypt::Password.create("password") %>` and `<%= 2.days.ago %>` — dynamic values at fixture load time.
- **Fast.** A 500-test suite with fixtures runs 2-5x faster than the same suite with FactoryBot creates, because there are zero INSERTs per test.

## When To Use Factories Instead

Sometimes fixtures aren't enough. Use FactoryBot (or fabrication) alongside fixtures for:

```ruby
# test/test_helper.rb
require "factory_bot_rails"

class ActiveSupport::TestCase
  include FactoryBot::Syntax::Methods
end
```

```ruby
# Use factories when you need MANY records with variations
test "pagination with 50 orders" do
  50.times { |i| create(:order, user: users(:alice), reference: "ORD-#{i.to_s.rjust(6, '0')}") }

  get orders_path, params: { page: 1, per: 25 }

  assert_response :success
  assert_select ".order-row", count: 25
end

# Use factories when the variation is the point of the test
test "discount tiers" do
  small_order = create(:order, total: 50_00)
  medium_order = create(:order, total: 200_00)
  large_order = create(:order, total: 1000_00)

  assert_equal 0, DiscountCalculator.call(small_order)
  assert_equal 10_00, DiscountCalculator.call(medium_order)
  assert_equal 100_00, DiscountCalculator.call(large_order)
end
```

## The Hybrid Approach

Use fixtures for stable reference data (users, products, roles, config) and factories for test-specific variations:

```ruby
class OrderTest < ActiveSupport::TestCase
  # Fixtures for the user (stable, referenced everywhere)
  # Factory for the order (specific to this test's needs)

  test "high-value orders require manager approval" do
    order = create(:order, user: users(:alice), total: 10_000_00)

    assert_predicate order, :requires_approval?
  end

  test "standard orders do not require approval" do
    # Fixture order is $50 — no approval needed
    refute_predicate orders(:pending_order), :requires_approval?
  end
end
```

## Anti-Pattern

Fixtures that are fragile or hard to maintain:

```yaml
# BAD: 200 fixtures with unclear relationships
order_1:
  user_id: 1
  status: pending
  total: 100

order_2:
  user_id: 1
  status: shipped
  total: 200

# ... 198 more
```

## Why This Is Bad

- **Raw IDs instead of labels.** `user_id: 1` breaks if fixture loading order changes. Use `user: alice` instead.
- **Too many fixtures.** If you need 200 orders for one test, use a factory loop. Fixtures are for stable reference data, not bulk test data.
- **No naming convention.** `order_1` tells you nothing. `pending_order`, `shipped_order`, `bobs_cancelled_order` are self-documenting.

## Fixture Naming Conventions

Name fixtures by their distinguishing characteristic:

```yaml
# Good names — describe what makes this fixture special
pending_order:    # Status-focused
shipped_order:
high_value_order: # Amount-focused
expired_order:    # Time-focused

# Bad names — meaningless
order_1:
order_2:
test_order:
```
