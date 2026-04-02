# RSpec: build_stubbed vs build vs create

## Pattern

Choose the cheapest factory strategy that satisfies the test. Default to `build_stubbed`, fall back to `build`, use `create` only when the test genuinely needs a persisted database record.

```ruby
RSpec.describe Order do
  # FASTEST: No database, no save, generates a fake id
  # Use for: testing methods that don't touch the DB
  let(:order) { build_stubbed(:order, total: 100.00) }

  describe "#discounted_total" do
    it "applies 10% discount" do
      expect(order.discounted_total).to eq(90.00)
    end
  end

  describe "#high_value?" do
    let(:cheap_order) { build_stubbed(:order, total: 50) }
    let(:expensive_order) { build_stubbed(:order, total: 500) }

    it "returns true for orders over 200" do
      expect(expensive_order.high_value?).to be true
      expect(cheap_order.high_value?).to be false
    end
  end
end
```

```ruby
RSpec.describe Order do
  # MEDIUM: In-memory object, not saved. Has valid attributes.
  # Use for: testing validations, or when you need to call .save yourself
  let(:order) { build(:order) }

  describe "validations" do
    it "requires a shipping address" do
      order.shipping_address = nil
      expect(order).not_to be_valid
      expect(order.errors[:shipping_address]).to include("can't be blank")
    end

    it "is valid with all required attributes" do
      expect(order).to be_valid
    end
  end
end
```

```ruby
RSpec.describe Order do
  # SLOWEST: Writes to database. Generates real id, timestamps, etc.
  # Use for: testing scopes, queries, uniqueness, DB constraints, and associations that query
  let(:user) { create(:user) }

  describe ".recent" do
    let!(:new_order) { create(:order, user: user, created_at: 1.day.ago) }
    let!(:old_order) { create(:order, user: user, created_at: 1.year.ago) }

    it "returns orders from the last 30 days" do
      expect(user.orders.recent).to eq([new_order])
    end
  end

  describe ".total_revenue" do
    before do
      create(:order, user: user, total: 100)
      create(:order, user: user, total: 250)
    end

    it "sums all order totals" do
      expect(user.orders.total_revenue).to eq(350)
    end
  end
end
```

The decision tree:

```
Does the test need the record in the database?
├── YES (scopes, queries, uniqueness, associations that query) → create
└── NO
    ├── Does the test call .save, .valid?, or .errors? → build
    └── NO (testing return values, calculations, formatting) → build_stubbed
```

## Why This Is Good

- **Speed.** `build_stubbed` is 10-50x faster than `create`. It skips database writes, transactions, callbacks, and index updates. In a 2,000-spec suite, choosing the right strategy can save 5-10 minutes of run time.
- **Isolation.** `build_stubbed` tests logic in complete isolation from the database. If the test passes, the method works regardless of database state.
- **Clearer intent.** When a test uses `create`, it signals "this test depends on the database." When it uses `build_stubbed`, it signals "this test is about pure logic." Readers immediately understand the scope.
- **Less factory overhead.** `build_stubbed` doesn't trigger `after_create` callbacks or cascade through association chains. A stubbed order doesn't create a real user, real line items, and real products.

## Anti-Pattern

Using `create` for everything because "it's easier" or "just in case":

```ruby
RSpec.describe Order do
  # SLOW: Every test creates 3+ database records
  let(:user) { create(:user) }
  let(:product) { create(:product) }
  let(:order) { create(:order, user: user) }
  let(:line_item) { create(:line_item, order: order, product: product) }

  describe "#high_value?" do
    it "returns true over 200" do
      # This test only checks a comparison: total > 200
      # It does NOT need any database records
      order.total = 500
      expect(order.high_value?).to be true
    end
  end

  describe "#formatted_total" do
    it "formats as currency" do
      # This test only checks string formatting
      # 4 database records created for zero reason
      expect(order.formatted_total).to eq("$100.00")
    end
  end
end
```

## Why This Is Bad

- **4 INSERT statements for a string formatting test.** The `formatted_total` test checks `sprintf` behavior. It needs zero database interaction, yet it creates a user, product, order, and line item.
- **Factory chain cascades.** `create(:order)` triggers `create(:user)` via the association. `create(:line_item)` triggers `create(:product)` and `create(:order)`. One `create` can cascade into 5+ INSERTs.
- **Slower test suite.** Across hundreds of tests, unnecessary `create` calls add up to minutes. A test suite that should run in 30 seconds takes 3 minutes.
- **Fragile.** Database-backed tests can fail for reasons unrelated to the behavior being tested — unique constraint violations from other test data, unexpected callbacks, or association validation errors.

## When To Apply

**Use `build_stubbed` when:**
- Testing instance methods that compute, format, or return values (`#total`, `#display_name`, `#high_value?`)
- Testing methods that check object state without querying (`#pending?`, `#can_cancel?`)
- Building objects to pass into service objects or other units under test
- You need an object with an `id` but don't need it in the database

**Use `build` when:**
- Testing model validations (`.valid?`, `.errors`)
- Testing `before_validation` or `before_save` callbacks
- You need to call `.save` in the test and check the result
- Building an object that will be passed to `create` or `save` explicitly

**Use `create` when:**
- Testing database scopes and queries (`.where`, `.recent`, `.active`)
- Testing uniqueness validations (need a real record to conflict with)
- Testing `has_many` / `belongs_to` associations that are loaded via query
- Testing `after_create` or `after_commit` callbacks
- Testing code that calls `.reload`
- Testing counter caches or database-computed columns

## When NOT To Apply

- Don't overthink it for one-off tests. If a test file has 3 examples and they all need `create`, just use `create`. The optimization matters at scale — hundreds of tests, not three.
- Don't `build_stubbed` when the method under test calls `.reload`, `.save`, or queries the database. It will raise or return stale data.

## Edge Cases

**`build_stubbed` and associations:**
Stubbed associations work for `belongs_to` (the foreign key is set). They don't work for `has_many` queries (no database to query against).

```ruby
order = build_stubbed(:order)
order.user          # Works — returns a stubbed user
order.line_items    # Returns empty collection — no DB to query
```

If you need associations, stub them manually or use `build_stubbed` with inline assignment:

```ruby
items = build_stubbed_list(:line_item, 3)
order = build_stubbed(:order)
allow(order).to receive(:line_items).and_return(items)
```

**`build_stubbed` and `.persisted?`:**
Stubbed objects return `true` for `.persisted?` and have a fake `id`. This makes them behave like saved records in most contexts — useful for testing path helpers, serializers, and view rendering.

**Testing both validation and persistence:**
Split into two tests. Validation test uses `build`. Persistence test uses `create`.

```ruby
describe "email" do
  it "validates format" do
    user = build(:user, email: "invalid")
    expect(user).not_to be_valid
  end

  it "enforces uniqueness in database" do
    create(:user, email: "taken@example.com")
    duplicate = build(:user, email: "taken@example.com")
    expect(duplicate).not_to be_valid
  end
end
```
