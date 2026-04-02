# Minitest: Test Structure and Conventions

## Pattern

Minitest ships with Ruby — no extra gems needed. It provides two styles: `Minitest::Test` (classic xUnit) and `Minitest::Spec` (describe/it blocks). Both are fast, simple, and explicit. Choose one style per project and stick with it.

### Classic Style (Minitest::Test)

```ruby
# test/models/order_test.rb
require "test_helper"

class OrderTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @order = orders(:pending_order)
  end

  test "calculates total from line items" do
    line_item = LineItem.create!(order: @order, product: products(:widget), quantity: 2, unit_price: 10_00)

    assert_equal 20_00, @order.reload.total
  end

  test "requires a shipping address" do
    order = Order.new(user: @user, shipping_address: nil)

    assert_not order.valid?
    assert_includes order.errors[:shipping_address], "can't be blank"
  end

  test "pending? returns true for pending orders" do
    assert_predicate @order, :pending?
  end

  test "pending? returns false for shipped orders" do
    @order.update!(status: :shipped)

    refute_predicate @order, :pending?
  end

  test ".recent returns orders from the last 30 days" do
    old_order = Order.create!(user: @user, shipping_address: "123 Main", created_at: 60.days.ago)

    recent = Order.recent

    assert_includes recent, @order
    refute_includes recent, old_order
  end
end
```

### Spec Style (Minitest::Spec)

```ruby
# test/models/order_spec.rb
require "test_helper"

describe Order do
  let(:user) { users(:alice) }
  let(:order) { orders(:pending_order) }

  describe "#total" do
    it "calculates from line items" do
      LineItem.create!(order: order, product: products(:widget), quantity: 2, unit_price: 10_00)

      _(order.reload.total).must_equal 20_00
    end
  end

  describe "validations" do
    it "requires shipping address" do
      order = Order.new(user: user, shipping_address: nil)

      _(order).wont_be :valid?
      _(order.errors[:shipping_address]).must_include "can't be blank"
    end
  end

  describe ".recent" do
    it "excludes orders older than 30 days" do
      old_order = Order.create!(user: user, shipping_address: "123 Main", created_at: 60.days.ago)

      _(Order.recent).must_include order
      _(Order.recent).wont_include old_order
    end
  end
end
```

### The test_helper.rb

```ruby
# test/test_helper.rb
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/autorun"
require "minitest/pride"      # Colorful output
require "webmock/minitest"    # Stub HTTP requests

class ActiveSupport::TestCase
  # Run tests in parallel
  parallelize(workers: :number_of_processors)

  # Use fixtures
  fixtures :all

  # Shared helpers available in all tests
  def sign_in(user)
    post login_path, params: { email: user.email, password: "password" }
  end

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end
end

class ActionDispatch::IntegrationTest
  # Helpers for integration tests
  def auth_headers(user)
    { "Authorization" => "Bearer #{user.api_keys.first.raw_key}" }
  end
end
```

## Why This Is Good

- **Ships with Ruby.** No Gemfile additions, no version conflicts, no `bundle install` waiting. It's always there.
- **Fast by default.** Minitest is ~5x faster to boot than RSpec. On a 500-test suite, this can save 3-5 seconds per run.
- **Plain Ruby.** Tests are classes with methods. No DSL magic, no `let` memoization surprises, no hidden context. Everything is explicit.
- **Fixtures over factories.** Rails fixtures load once, wrap in transactions, and are instant. No N factory creates per test.
- **Parallel by default.** `parallelize(workers: :number_of_processors)` runs tests across CPU cores out of the box.

## Anti-Pattern

Overly complex test setup that mimics RSpec patterns instead of using Minitest idioms:

```ruby
# BAD: Fighting Minitest to write RSpec-style tests
class OrderTest < ActiveSupport::TestCase
  # Don't try to replicate RSpec's let/subject/context nesting
  def setup
    @company = Company.create!(name: "Acme")
    @user = User.create!(email: "test@example.com", company: @company)
    @product = Product.create!(name: "Widget", price: 10_00, company: @company)
    @order = Order.create!(user: @user, shipping_address: "123 Main")
    @line_item = LineItem.create!(order: @order, product: @product, quantity: 2, unit_price: 10_00)
  end

  # Every test pays for all 5 creates even if it only needs @user
end
```

## Why This Is Bad

- **Setup creates everything for every test.** A validation test that only needs an Order still creates Company, User, Product, and LineItem.
- **Fixtures solve this.** Define the data once in YAML, load it once per suite, wrap in transactions. Zero per-test cost.

## When To Apply

- **Every Ruby or Rails project.** Minitest is the Rails default. New projects should start with it unless the team has strong RSpec preferences.
- **When test speed matters.** Minitest boots faster and runs faster. For CI-heavy teams, this compounds.
- **When simplicity matters.** Junior developers and contributors learn Minitest in minutes. It's just Ruby.

## When NOT To Apply

- **The team already uses RSpec.** Don't switch mid-project. The cost of rewriting tests exceeds any speed benefit.
- **You need advanced matchers.** RSpec's `have_attributes`, `change { }.by`, `contain_exactly` are more expressive for complex assertions. Minitest can do the same but with more verbose code.
