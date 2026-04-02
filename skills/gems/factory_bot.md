# Gem: FactoryBot

## What It Is

FactoryBot creates test data for RSpec and Minitest. It replaces fixtures with programmatic factories that produce valid ActiveRecord objects with minimal boilerplate. It's the most widely used test data library in Rails.

## Setup Done Right

```ruby
# Gemfile (test group)
gem 'factory_bot_rails'

# spec/support/factory_bot.rb
RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
end
```

## Gotcha #1: Factory Chains Create Way More Records Than You Think

Every `belongs_to` association in a factory triggers a `create` of the associated record. A deeply nested factory can create 10+ records when you only asked for 1.

```ruby
# These factories look innocent...
FactoryBot.define do
  factory :line_item do
    order           # Creates an order
    product         # Creates a product
    quantity { 1 }
  end

  factory :order do
    user            # Creates a user
    shipping_address { "123 Main St" }
  end

  factory :user do
    company         # Creates a company
    email { "user@example.com" }
  end

  factory :company do
    name { "Acme Inc" }
    plan            # Creates a plan
  end
end

# This single line...
create(:line_item)
# Actually creates: plan → company → user → order → product → line_item
# That's 6 INSERT statements for ONE line item!
```

**Fix: Use `build_stubbed` when you don't need the DB, and be deliberate about associations:**

```ruby
# For unit tests — zero database hits
line_item = build_stubbed(:line_item)

# When you need a real record but want to control associations
user = create(:user, company: nil)  # Skip company creation
order = create(:order, user: user)  # Reuse the user
create(:line_item, order: order)    # Only creates product + line_item
```

## Gotcha #2: Sequences vs Hardcoded Values

Unique fields without sequences cause test failures that depend on execution order.

```ruby
# WRONG: Hardcoded unique field — second create fails
factory :user do
  email { "test@example.com" }  # Duplicate on second create!
end

create(:user)  # Works
create(:user)  # ActiveRecord::RecordNotUnique: email already taken

# RIGHT: Use sequences for any unique field
factory :user do
  sequence(:email) { |n| "user#{n}@example.com" }
  name { "Jane Doe" }
end

create(:user).email  # "user1@example.com"
create(:user).email  # "user2@example.com"
```

**The trap:** Tests pass when run individually but fail when run together. The first test creates `test@example.com`, the second tries to create it again. Sequences prevent this.

## Gotcha #3: `create` vs `build` vs `build_stubbed` — Wrong Choice Wastes Time

```ruby
# WRONG: Using create when build_stubbed would work
RSpec.describe Order do
  let(:order) { create(:order) }  # Writes to DB unnecessarily

  it "calculates total" do
    # This test only calls order.total — it never queries the DB
    expect(order.total).to eq(0)
  end
end

# RIGHT: Match the factory strategy to the test's needs
RSpec.describe Order do
  let(:order) { build_stubbed(:order, total: 100) }  # No DB hit

  it "calculates total" do
    expect(order.total).to eq(100)
  end
end
```

Decision tree:
- **Does the test query the DB (scopes, joins, reload)?** → `create`
- **Does the test call `.valid?`, `.save`, or `.errors`?** → `build`
- **Does the test only call instance methods?** → `build_stubbed`

## Gotcha #4: Traits — Compose, Don't Create New Factories

```ruby
# WRONG: Separate factories for every variation
factory :pending_order do
  status { :pending }
  user
end

factory :shipped_order do
  status { :shipped }
  shipped_at { 1.day.ago }
  user
end

factory :high_value_shipped_order do
  status { :shipped }
  shipped_at { 1.day.ago }
  total { 500 }
  user
end

# RIGHT: One factory with composable traits
factory :order do
  user
  sequence(:reference) { |n| "ORD-#{n.to_s.rjust(6, '0')}" }
  status { :pending }
  total { 100 }

  trait :shipped do
    status { :shipped }
    shipped_at { 1.day.ago }
  end

  trait :cancelled do
    status { :cancelled }
    cancelled_at { 1.hour.ago }
  end

  trait :high_value do
    total { 500 }
  end

  trait :with_line_items do
    transient do
      item_count { 2 }
    end

    after(:create) do |order, ctx|
      create_list(:line_item, ctx.item_count, order: order)
    end
  end
end

# Compose traits as needed
create(:order, :shipped)
create(:order, :shipped, :high_value)
create(:order, :with_line_items, item_count: 5)
create(:order, :cancelled, total: 0)
```

## Gotcha #5: `after(:create)` Blocks Break `build_stubbed`

```ruby
# WRONG: after(:create) prevents build_stubbed from working
factory :order do
  after(:create) do |order|
    create(:line_item, order: order)  # Only runs on create, not build_stubbed
  end
end

build_stubbed(:order)
# Works — but has no line items (after(:create) didn't run)
# Tests that expect line items fail silently

# RIGHT: Use traits for optional associations
factory :order do
  # Base factory has no line items

  trait :with_line_items do
    after(:create) do |order|
      create_list(:line_item, 2, order: order)
    end
  end
end

create(:order, :with_line_items)  # Has line items
build_stubbed(:order)              # No line items, but that's expected
```

## Gotcha #6: Faker Slows Tests and Creates Flaky Failures

```ruby
# WRONG: Faker for every attribute
factory :user do
  name { Faker::Name.name }         # Random every test run
  email { Faker::Internet.email }    # Can generate duplicates!
  bio { Faker::Lorem.paragraph(sentence_count: 10) }  # Slow, nobody reads it
end

# RIGHT: Static defaults, sequences for unique fields
factory :user do
  name { "Jane Doe" }
  sequence(:email) { |n| "user#{n}@example.com" }
  # No bio — keep it nil unless a test specifically needs it
end
```

**The traps:**
- Faker generates random data. Your test passes 99% of the time but fails when Faker generates a name over 100 characters (your validation limit).
- Faker::Internet.email can generate the same email twice. Unlike sequences, it doesn't guarantee uniqueness.
- Faker is slow — it generates random data on every call. Across 2,000 factory calls, this adds seconds.

## Gotcha #7: Lint Your Factories

```ruby
# spec/factories_spec.rb — catches broken factories early
RSpec.describe "FactoryBot factories" do
  it "has valid factories" do
    FactoryBot.lint(traits: true)
  end
end
```

This creates every factory with every trait and calls `.valid?` on each. It catches:
- Missing required fields
- Broken associations
- Invalid trait combinations
- Sequences that produce invalid data

Run it in CI — it's the first test to fail when someone adds a model validation without updating the factory.

## Do's and Don'ts Summary

**DO:**
- Use `build_stubbed` by default, `build` for validation tests, `create` only when the DB is needed
- Use sequences for every unique field (email, reference, slug)
- Use traits for variations — compose them, don't create separate factories
- Use transient attributes for configurable association creation
- Use static values for non-unique fields
- Lint your factories in CI
- Keep base factories minimal — only required fields

**DON'T:**
- Don't use `create` when `build_stubbed` would work
- Don't use Faker for factory defaults (slow, flaky, non-unique)
- Don't put `after(:create)` in the base factory — use traits
- Don't create separate factories for variations — use traits
- Don't forget to update factories when you add model validations
- Don't let factories silently create 10+ records via association chains
