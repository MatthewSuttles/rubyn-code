# RSpec: Mocking and Stubbing

## Pattern

Use `instance_double` for type-safe mocks. Stub external dependencies, not the object under test. Prefer dependency injection over global stubs. Use `allow` for setup, `expect` for assertions.

```ruby
# GOOD: instance_double verifies the interface exists
RSpec.describe Orders::CreateService do
  let(:user) { build_stubbed(:user) }
  let(:mailer) { instance_double(OrderMailer) }
  let(:message) { instance_double(ActionMailer::MessageDelivery) }

  before do
    allow(OrderMailer).to receive(:confirmation).and_return(message)
    allow(message).to receive(:deliver_later)
  end

  it "sends a confirmation email" do
    expect(OrderMailer).to receive(:confirmation).with(an_instance_of(Order))
    described_class.call(valid_params, user)
  end
end
```

```ruby
# GOOD: Stub external HTTP dependency
RSpec.describe Embeddings::EmbeddingClient do
  let(:client) { described_class.new(base_url: "http://localhost:8000") }

  before do
    stub_request(:post, "http://localhost:8000/embed")
      .with(body: hash_including("texts"))
      .to_return(
        status: 200,
        body: { embeddings: [[0.1, 0.2, 0.3]], dimensions: 1024, count: 1 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "returns embeddings from the service" do
    result = client.embed(["def hello; end"])
    expect(result.first.length).to eq(3)
  end
end
```

```ruby
# GOOD: Dependency injection makes stubbing natural
class Orders::CreateService
  def initialize(mailer: OrderMailer, notifier: WarehouseNotifier)
    @mailer = mailer
    @notifier = notifier
  end

  def call(params, user)
    order = user.orders.create!(params)
    @mailer.confirmation(order).deliver_later
    @notifier.notify(order)
    order
  end
end

# Test: inject doubles instead of patching globals
RSpec.describe Orders::CreateService do
  let(:mailer) { instance_double(OrderMailer) }
  let(:notifier) { instance_double(WarehouseNotifier) }
  let(:service) { described_class.new(mailer: mailer, notifier: notifier) }

  before do
    allow(mailer).to receive_message_chain(:confirmation, :deliver_later)
    allow(notifier).to receive(:notify)
  end

  it "notifies the warehouse" do
    expect(notifier).to receive(:notify).with(an_instance_of(Order))
    service.call(valid_params, user)
  end
end
```

`allow` vs `expect`:

```ruby
# allow: Setup — "if this gets called, return this"
# No failure if it's never called
allow(service).to receive(:call).and_return(result)

# expect: Assertion — "this MUST be called"
# Fails if it's never called
expect(service).to receive(:call).with(expected_args)
```

## Why This Is Good

- **`instance_double` catches interface drift.** If you rename `OrderMailer#confirmation` to `OrderMailer#order_confirmation`, tests using `instance_double(OrderMailer)` that stub `:confirmation` immediately fail. A plain `double` wouldn't catch this — the test would pass while production breaks.
- **Stubbing externals isolates the unit.** The service test doesn't depend on a running email server, a warehouse API, or an embedding service. It tests the orchestration logic in isolation.
- **Dependency injection is better than global patching.** `allow(OrderMailer).to receive(...)` patches a global constant. Injecting a double via the constructor is explicit, doesn't affect other tests, and doesn't depend on load order.
- **`allow` for setup, `expect` for assertions** keeps intent clear. Setup stubs say "the world looks like this." Assertion mocks say "this thing must happen."
- **WebMock for HTTP.** `stub_request` prevents real HTTP calls in tests, returns controlled responses, and verifies the request was made correctly.

## Anti-Pattern

Mocking the object under test, overuse of `any_instance`, and testing implementation details:

```ruby
# BAD: Stubbing the object under test
RSpec.describe Order do
  it "calculates total" do
    order = build(:order)
    allow(order).to receive(:line_items).and_return([
      double(total: 10), double(total: 20)
    ])
    expect(order.calculate_total).to eq(30)
  end
end

# BAD: any_instance_of — fragile, global, affects all instances
RSpec.describe OrdersController do
  it "creates an order" do
    allow_any_instance_of(Order).to receive(:save).and_return(true)
    post :create, params: { order: valid_params }
    expect(response).to redirect_to(orders_path)
  end
end

# BAD: Testing method call sequence — implementation detail
RSpec.describe Orders::CreateService do
  it "creates then sends then notifies" do
    expect(Order).to receive(:create!).ordered
    expect(OrderMailer).to receive(:confirmation).ordered
    expect(WarehouseNotifier).to receive(:notify).ordered
    described_class.call(params, user)
  end
end

# BAD: Plain doubles with no type checking
let(:user) { double("User", name: "Alice", save: true, banana: "yellow") }
# "banana" isn't a User method — double won't catch this
```

## Why This Is Bad

- **Stubbing the object under test.** If you stub `order.line_items`, you're not testing `calculate_total` against real data — you're testing that it sums a stubbed array. The real method might have a bug in how it queries line items, and you'll never know.
- **`any_instance_of` is global.** It affects every instance of the class in the entire test, including instances created inside the code under test. It's unpredictable, hard to scope, and a sign of untestable design.
- **Testing call order is brittle.** If someone reorders the operations (notify before mail, or in parallel), the test breaks even though the behavior is correct. Test outcomes, not sequence.
- **Plain doubles don't verify interfaces.** `double("User", banana: "yellow")` creates a fake that responds to `:banana`. If `User` doesn't have a `banana` method, you'll never know until production. `instance_double(User)` would catch this immediately.

## When To Apply

- **Stub external services.** HTTP APIs, email delivery, file storage, third-party SDKs — anything outside your application boundary. Use WebMock for HTTP, instance_double for Ruby dependencies.
- **Stub slow operations in unit tests.** Database queries in a service spec that's testing logic, not persistence. But prefer `build_stubbed` over mocking AR.
- **Use `expect(...).to receive` when verifying side effects.** "Did the mailer get called?" is a legitimate assertion. "Did the service call `create!` then `deliver_later` in that order?" is not.
- **Inject dependencies** when a class collaborates with external services. Constructor injection (`def initialize(mailer:)`) makes testing trivial.

## When NOT To Apply

- **Don't mock what you can build.** `build_stubbed(:user)` is better than `instance_double(User)` when you need a realistic user object. Doubles are for collaborators you want to isolate from, not for the subject's own data.
- **Don't mock ActiveRecord queries in model specs.** If you're testing a scope, run the real query against the test database. Mocking `where` defeats the purpose.
- **Don't use mocks in integration/system tests.** These tests exist to verify the full stack. Mocking within them undermines their value.
- **Don't mock more than 2-3 dependencies.** If a test needs 5 mocks to set up, the class under test has too many dependencies. Refactor the class before adding more mocks.

## Edge Cases

**`class_double` for class method stubbing:**

```ruby
auth_service = class_double(AuthService, verify: true)
stub_const("AuthService", auth_service)
expect(auth_service).to receive(:verify).with("token").and_return(user)
```

**`receive_message_chain` — use sparingly:**

```ruby
# Acceptable for mailer chains
allow(OrderMailer).to receive_message_chain(:confirmation, :deliver_later)

# NOT acceptable for business logic chains — sign of Law of Demeter violation
allow(order).to receive_message_chain(:user, :company, :billing_address, :country)
# Fix the code: order.billing_country instead of 4-deep chain
```

**Verifying arguments:**

```ruby
expect(mailer).to receive(:confirmation).with(
  having_attributes(id: order.id, total: 100)
)

expect(client).to receive(:post).with(
  "/api/v1/orders",
  hash_including(status: "pending")
)
```

**Spy pattern (assert after the fact):**

```ruby
notifier = instance_double(WarehouseNotifier)
allow(notifier).to receive(:notify)

service = described_class.new(notifier: notifier)
service.call(params, user)

expect(notifier).to have_received(:notify).with(an_instance_of(Order))
```

This is useful when you want `allow` in setup and assertion at the end, rather than `expect` before the action.
