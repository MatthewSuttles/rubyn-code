# RSpec: let vs let!

## Pattern

Use `let` (lazy) by default. Use `let!` (eager) only when the record must exist in the database before the example runs, and no example in the group references it directly.

```ruby
RSpec.describe Order do
  # CORRECT: Lazy — only created when an example calls `user`
  let(:user) { create(:user) }

  # CORRECT: Lazy — only created when an example calls `order`
  let(:order) { create(:order, user: user) }

  describe "#total" do
    # These line items are only created for examples that call `line_items`
    let(:line_items) do
      [
        create(:line_item, order: order, quantity: 2, unit_price: 10.00),
        create(:line_item, order: order, quantity: 1, unit_price: 25.00)
      ]
    end

    it "calculates from line items" do
      line_items # Trigger creation
      expect(order.reload.total).to eq(45.00)
    end
  end

  describe ".recent" do
    # CORRECT use of let! — these must exist BEFORE the scope query runs.
    # No example references `old_order` directly, but it must be in the DB
    # for the scope to correctly exclude it.
    let!(:recent_order) { create(:order, created_at: 1.day.ago) }
    let!(:old_order) { create(:order, created_at: 1.year.ago) }

    it "returns orders from the last 30 days" do
      expect(Order.recent).to include(recent_order)
      expect(Order.recent).not_to include(old_order)
    end
  end
end
```

## Why This Is Good

- **Lazy `let` avoids unnecessary DB hits.** If an example doesn't reference a `let` variable, the record is never created. In a describe block with 10 examples where only 3 need a specific record, you save 7 unnecessary INSERT statements.
- **Each example is self-documenting.** When you see `let(:order)` used in an example, you know that example needs an order. With `let!`, you have to mentally track "which records exist before every example runs?" even in examples that don't use them.
- **Faster test suite.** Lazy evaluation means the minimum number of records are created per example. In a large test suite, this compounds into minutes saved.
- **Memoized per example.** `let` evaluates once per example and caches. Calling `user` three times in one example hits the database once. No need for instance variables.

## Anti-Pattern

Using `let!` everywhere "just to be safe":

```ruby
RSpec.describe Order do
  let!(:user) { create(:user) }
  let!(:admin) { create(:user, role: :admin) }
  let!(:product) { create(:product) }
  let!(:category) { create(:category) }
  let!(:order) { create(:order, user: user) }
  let!(:line_item) { create(:line_item, order: order, product: product) }
  let!(:shipping_rate) { create(:shipping_rate) }

  describe "#total" do
    it "calculates correctly" do
      # Only needs order and line_item, but ALL 7 records are created
      expect(order.total).to eq(line_item.quantity * line_item.unit_price)
    end
  end

  describe "#shipped?" do
    it "returns false when pending" do
      # Only needs order, but ALL 7 records are created
      expect(order.shipped?).to be false
    end
  end
end
```

## Why This Is Bad

- **Every example pays for every record.** 7 INSERT statements run before every single example, even if the example only needs 1 record. With 20 examples in this describe block, that's 140 INSERTs instead of ~40.
- **Hides dependencies.** When everything is `let!`, you can't tell which records an example actually needs by reading it. The implicit "everything exists" makes the test harder to understand and maintain.
- **Masks missing associations.** If an example works only because `let!(:product)` happens to exist, removing it later breaks the test in a confusing way. With `let`, the dependency is explicit — the example calls `product` or it doesn't.
- **Factory chain explosion.** If `create(:order)` creates a user, and `create(:line_item)` creates a product and a category, `let!` on all of them creates duplicate records you never asked for.

## When To Apply

Use `let!` ONLY when ALL of these are true:

1. The record must exist in the database BEFORE the example runs
2. The example doesn't reference the variable directly — it's testing a query/scope that should find (or exclude) the record
3. There's no other way to trigger the creation

The classic case is **testing scopes and queries**:

```ruby
describe ".active" do
  let!(:active_user) { create(:user, active: true) }
  let!(:inactive_user) { create(:user, active: false) }

  it "returns only active users" do
    # Both must exist in DB before User.active runs
    # The example references active_user for the assertion but
    # inactive_user must exist to prove exclusion
    expect(User.active).to eq([active_user])
  end
end
```

## When NOT To Apply

- **The example references the variable directly.** If the example calls `order`, use `let` — it will be created on first reference.
- **You're "not sure if it needs to exist first."** Default to `let`. If the test fails because the record doesn't exist, then switch to `let!` for that specific variable. Don't preemptively use `let!`.
- **You're setting up context for a single example.** Use inline `create` inside the example instead:

```ruby
it "rejects duplicate emails" do
  create(:user, email: "taken@example.com")
  duplicate = build(:user, email: "taken@example.com")
  expect(duplicate).not_to be_valid
end
```

## Edge Cases

**`let` inside a `before` block:**
Don't. If you need something to exist before all examples, use `let!` or a `before` block with `create` directly. Calling `let` variables inside `before` works but obscures intent.

```ruby
# Clear intent
let!(:admin) { create(:user, role: :admin) }

# Also clear
before { create(:user, role: :admin) }

# Confusing — looks lazy but is eager because before forces evaluation
let(:admin) { create(:user, role: :admin) }
before { admin }
```

**`let` with `build_stubbed`:**
Always prefer `let(:user) { build_stubbed(:user) }` when the test doesn't need a database record. This is even faster than lazy `let` with `create` because no DB hit ever occurs.

**Nested `describe` blocks with `let`:**
Inner `let` overrides outer `let` with the same name. This is useful for testing variations:

```ruby
let(:user) { create(:user, plan: :free) }

context "with pro plan" do
  let(:user) { create(:user, plan: :pro) }
  it { expect(user.can_export?).to be true }
end

context "with free plan" do
  it { expect(user.can_export?).to be false }
end
```
