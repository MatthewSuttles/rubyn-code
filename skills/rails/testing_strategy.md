# Rails: Testing Strategy (What to Test Where)

## Pattern

Test each layer of your Rails app at the right level of abstraction. Unit tests for logic, integration tests for HTTP, system tests for user journeys. The pyramid: many unit tests, fewer integration tests, few system tests.

### The Testing Pyramid for Rails

```
        /  System Tests  \        ← 10-30 tests: Critical user journeys (browser)
       / Integration Tests \      ← 50-200 tests: Every endpoint (HTTP)
      /    Service Specs    \     ← 50-200 tests: Business logic (Ruby)
     /     Model Specs       \    ← 100-500 tests: Validations, scopes, methods
    /   Factories + Fixtures   \  ← Support: Test data infrastructure
```

### What to Test at Each Layer

#### Models — Validations, Scopes, Instance Methods

```ruby
# spec/models/order_spec.rb (RSpec) or test/models/order_test.rb (Minitest)
# Test: validations, scopes, calculated fields, state predicates
# Don't test: associations (Rails tests these), framework behavior

# Validations
it "requires shipping address" do
  order = build(:order, shipping_address: nil)
  expect(order).not_to be_valid
  expect(order.errors[:shipping_address]).to include("can't be blank")
end

# Scopes — need database records
describe ".recent" do
  let!(:new_order) { create(:order, created_at: 1.day.ago) }
  let!(:old_order) { create(:order, created_at: 60.days.ago) }

  it "returns orders from the last 30 days" do
    expect(Order.recent).to include(new_order)
    expect(Order.recent).not_to include(old_order)
  end
end

# Instance methods — prefer build_stubbed
describe "#total" do
  it "sums line item amounts" do
    order = build_stubbed(:order)
    allow(order).to receive(:line_items).and_return([
      build_stubbed(:line_item, quantity: 2, unit_price: 10_00),
      build_stubbed(:line_item, quantity: 1, unit_price: 25_00)
    ])
    expect(order.total).to eq(45_00)
  end
end
```

#### Service Objects — Business Logic

```ruby
# spec/services/orders/create_service_spec.rb
# Test: success/failure paths, side effects, error handling
# Don't test: HTTP (that's integration tests), rendering

describe Orders::CreateService do
  let(:user) { create(:user) }

  it "creates an order and enqueues confirmation" do
    result = described_class.call(valid_params, user)

    expect(result).to be_success
    expect(result.order).to be_persisted
    expect(OrderConfirmationJob).to have_been_enqueued.with(result.order.id)
  end

  it "returns failure for invalid params" do
    result = described_class.call({ shipping_address: "" }, user)

    expect(result).to be_failure
    expect(result.error).to include("Shipping address")
  end

  it "does not enqueue jobs on failure" do
    described_class.call({ shipping_address: "" }, user)
    expect(OrderConfirmationJob).not_to have_been_enqueued
  end
end
```

#### Controllers / Endpoints — HTTP Integration

```ruby
# spec/requests/orders_spec.rb
# Test: status codes, redirects, response body, authentication, authorization
# Don't test: business logic (that's in service specs)

describe "POST /orders" do
  let(:user) { create(:user) }
  before { sign_in user }

  context "with valid params" do
    it "creates and redirects" do
      expect {
        post orders_path, params: { order: valid_params }
      }.to change(Order, :count).by(1)

      expect(response).to redirect_to(Order.last)
    end
  end

  context "with invalid params" do
    it "renders form with errors" do
      post orders_path, params: { order: { shipping_address: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  context "without authentication" do
    before { sign_out }

    it "redirects to login" do
      post orders_path, params: { order: valid_params }
      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
```

#### API Endpoints — JSON Integration

```ruby
# spec/requests/api/v1/orders_spec.rb
describe "GET /api/v1/orders" do
  let(:user) { create(:user) }
  let(:headers) { auth_headers(user) }

  it "returns orders as JSON" do
    create_list(:order, 3, user: user)

    get "/api/v1/orders", headers: headers

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["orders"].length).to eq(3)
    expect(json["orders"].first).to include("id", "reference", "status")
    expect(json["orders"].first).not_to include("password_digest", "api_cost_usd")
  end
end
```

#### Mailers — Content and Delivery

```ruby
# spec/mailers/order_mailer_spec.rb
# Test: recipients, subject, body content
# Don't test: delivery mechanism (Rails handles that)

describe OrderMailer do
  describe "#confirmation" do
    let(:order) { build_stubbed(:order, reference: "ORD-001") }
    let(:mail) { described_class.confirmation(order) }

    it "sends to the order's user" do
      expect(mail.to).to eq([order.user.email])
    end

    it "includes the order reference" do
      expect(mail.body.encoded).to include("ORD-001")
    end
  end
end
```

#### Jobs — Logic and Idempotency

```ruby
# spec/jobs/order_confirmation_job_spec.rb
# Test: the job's perform logic, idempotency, error handling
# Don't test: that ActiveJob works (framework responsibility)

describe OrderConfirmationJob do
  let(:order) { create(:order) }

  it "sends confirmation email" do
    expect { described_class.perform_now(order.id) }
      .to change { ActionMailer::Base.deliveries.count }.by(1)
  end

  it "is idempotent" do
    order.update!(confirmation_sent_at: 1.hour.ago)

    expect { described_class.perform_now(order.id) }
      .not_to change { ActionMailer::Base.deliveries.count }
  end
end
```

#### System Tests — User Journeys (Few, Critical)

```ruby
# spec/system/checkout_spec.rb
# Test: full user journey through the browser
# Don't test: every edge case (that's model + service specs)

it "places an order from the product page" do
  sign_in create(:user)
  visit products_path

  click_button "Add to Cart"
  click_link "Checkout"
  fill_in "Shipping address", with: "123 Main St"
  click_button "Place Order"

  expect(page).to have_content("Order placed")
end
```

### What NOT to Test

```ruby
# DON'T test framework behavior
it "has many line items" do
  expect(Order.reflect_on_association(:line_items).macro).to eq(:has_many)
end
# Rails already tests that has_many works. Test the behavior, not the declaration.

# DON'T test trivial methods
it "returns the name" do
  user = build(:user, name: "Alice")
  expect(user.name).to eq("Alice")
end
# This tests that attr_reader works. It always works.

# DON'T test private methods directly
it "builds the cache key" do
  expect(service.send(:build_cache_key, order)).to eq("orders:42")
end
# Test through the public interface. If the private method matters, it'll affect the output.
```

### Speed Budget

| Layer | Target per test | Count target | Total time target |
|---|---|---|---|
| Model specs | 1-5ms | 100-500 | < 5 seconds |
| Service specs | 5-20ms | 50-200 | < 5 seconds |
| Request specs | 10-50ms | 50-200 | < 10 seconds |
| Mailer specs | 5-10ms | 10-30 | < 1 second |
| Job specs | 5-20ms | 10-50 | < 2 seconds |
| System specs | 1-5s | 10-30 | < 60 seconds |
| **Full suite** | | **300-1000** | **< 90 seconds** |

If your suite exceeds these targets, profile with `--profile` and optimize the slowest tests first. The usual culprits: unnecessary `create` calls, missing `build_stubbed`, system tests that should be request tests.

## Why This Matters

Testing at the wrong layer wastes time. A validation test in a system spec takes 2 seconds. In a model spec, 2 milliseconds. That's a 1000x difference. Multiply by 100 tests and it's the difference between a 3-second suite and a 3-minute suite.

Test logic where it lives. Test HTTP at the HTTP layer. Test UI only for the critical paths.
