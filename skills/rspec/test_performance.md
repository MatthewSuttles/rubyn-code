# RSpec: Test Suite Performance

## Pattern

A fast test suite runs in under 60 seconds for 1,000 specs. Achieve this by minimizing database hits, choosing the cheapest factory strategy per test, avoiding unnecessary setup, and profiling regularly.

Core strategies ranked by impact:

**1. Use `build_stubbed` wherever possible**

```ruby
# FAST: Zero database hits
let(:user) { build_stubbed(:user) }
let(:order) { build_stubbed(:order, user: user, total: 100) }

it "calculates discount" do
  expect(order.discounted_total).to eq(90)
end
```

**2. Use `let` (lazy) instead of `let!` (eager)**

```ruby
# FAST: Only creates records that are actually referenced
let(:user) { create(:user) }
let(:order) { create(:order, user: user) }

# Only the examples that call `order` pay for its creation
```

**3. Minimize factory association chains**

```ruby
# BAD: Creates user, company, plan, 3 line items, 3 products, 3 categories
let(:order) { create(:order, :with_line_items) }

# GOOD: Only what this test needs
let(:order) { build_stubbed(:order, total: 100) }
```

**4. Use `before(:all)` / `before_all` for truly shared expensive setup**

```ruby
# With the test-prof gem's before_all (transaction-safe)
before_all do
  @reference_data = create(:pricing_table_with_100_rows)
end

# Standard before(:all) — use with caution, not wrapped in transaction
before(:all) do
  @admin = create(:user, :admin)
end
```

**5. Profile your test suite to find the bottlenecks**

```bash
# Find the 10 slowest examples
bundle exec rspec --profile 10

# Find the slowest factories (requires test-prof gem)
FPROF=1 bundle exec rspec

# Find examples that make the most DB queries
EVENT_PROF=sql.active_record bundle exec rspec
```

**6. Use `aggregate_failures` to reduce example count**

```ruby
# SLOW: 4 separate examples, each with their own setup
it "has a reference" do
  expect(order.reference).to be_present
end
it "has a status" do
  expect(order.status).to eq("pending")
end
it "belongs to a user" do
  expect(order.user).to eq(user)
end
it "has a created_at" do
  expect(order.created_at).to be_present
end

# FAST: 1 example, same assertions, same error detail on failure
it "has the expected attributes", :aggregate_failures do
  expect(order.reference).to be_present
  expect(order.status).to eq("pending")
  expect(order.user).to eq(user)
  expect(order.created_at).to be_present
end
```

**7. Parallelize with `parallel_tests`**

```ruby
# Gemfile
gem 'parallel_tests', group: :development

# Run on 4 cores
bundle exec parallel_rspec -n 4

# Database setup for parallel
rake parallel:setup
```

## Why This Is Good

- **Developer productivity.** A 30-second test suite gets run after every change. A 10-minute suite gets run before commits, maybe. A 30-minute suite gets run in CI only. Fast feedback loops produce better code.
- **CI costs.** CI minutes cost money. A test suite that runs in 60 seconds vs 10 minutes is a 10x cost difference over thousands of builds per month.
- **Developer morale.** Nobody enjoys waiting. A slow test suite creates friction that makes developers skip tests, run subsets, or push untested code.
- **Catch failures faster.** When tests run in 30 seconds, you run them after every change and catch bugs immediately. When they take 10 minutes, you batch changes and debugging becomes harder.

## Anti-Pattern

A test suite where every example creates a full object graph and runs expensive setup:

```ruby
RSpec.describe Order do
  let!(:company) { create(:company) }
  let!(:admin) { create(:user, :admin, company: company) }
  let!(:user) { create(:user, company: company) }
  let!(:product_a) { create(:product, :with_inventory, company: company) }
  let!(:product_b) { create(:product, :with_inventory, company: company) }
  let!(:order) { create(:order, :with_line_items, user: user, item_count: 3) }

  describe "#formatted_total" do
    it "returns a currency string" do
      # 15+ records created for a string formatting test
      expect(order.formatted_total).to match(/\$\d+\.\d{2}/)
    end
  end

  describe "#pending?" do
    it "returns true when status is pending" do
      # 15+ records created to test a boolean comparison
      expect(order.pending?).to be true
    end
  end
end
```

## Why This Is Bad

- **15+ INSERT statements per example.** With `let!`, every record is created before every example. 20 examples in this file = 300+ INSERTs.
- **90% of the setup is irrelevant.** `formatted_total` needs a number, not a company, admin, products, and inventory records.
- **Compounds across the suite.** If 50 spec files follow this pattern, the test suite creates 15,000+ unnecessary records per run.
- **Factory chains hide the cost.** `create(:order, :with_line_items)` looks like one record but cascades into order + user + company + 3 line items + 3 products = 9 INSERTs.

## When To Apply

Always. Test performance should be a continuous concern, not an afterthought.

**Before writing any spec, ask:**
1. Does this test need the database at all? → `build_stubbed`
2. Does it need the database but not the full object graph? → `create` with minimal attributes
3. Does it need a complex setup? → isolate the setup, share it via traits or `before_all`

**Regular maintenance:**
- Run `--profile 10` monthly to catch slow tests
- Install `test-prof` and run factory profiling when the suite slows down
- Set a CI budget: if the suite exceeds 2 minutes, investigate before adding more tests

## When NOT To Apply

- **Don't prematurely optimize.** A 10-spec file that runs in 2 seconds doesn't need profiling or `build_stubbed` rewrites. Focus on the slow files first.
- **Don't sacrifice readability for speed.** If using `create` makes a test dramatically clearer than a `build_stubbed` with 5 `allow` stubs, use `create`. Clarity wins when the speed difference is negligible.
- **System/feature tests are inherently slower.** They launch a browser and interact with full pages. Optimize them by having fewer of them (test critical paths only) rather than by cutting database setup.

## Edge Cases

**DatabaseCleaner strategies:**
Use `:transaction` strategy (default with RSpec Rails) for unit and request specs. Use `:truncation` or `:deletion` only for system specs that need JavaScript (and thus run outside the test transaction).

```ruby
# spec/support/database_cleaner.rb
RSpec.configure do |config|
  config.use_transactional_fixtures = true

  config.before(:each, type: :system) do
    DatabaseCleaner.strategy = :truncation
  end

  config.after(:each, type: :system) do
    DatabaseCleaner.clean
  end
end
```

**Shared test data across a describe block:**
`test-prof`'s `before_all` creates data once per describe block (wrapped in a transaction), not once per example. This is safe and dramatically faster than `let!` for read-only reference data.

```ruby
# Requires test-prof gem
before_all do
  @products = create_list(:product, 50)
end

it "searches products" do
  results = Product.search("widget")
  expect(results).to include(@products.first)
end
```

**Stubbing Time:**
Use `travel_to` instead of creating records with specific timestamps, then querying by date:

```ruby
it "returns recent orders" do
  travel_to(2.days.ago) { create(:order) }
  recent = create(:order)

  expect(Order.recent).to eq([recent])
end
```
