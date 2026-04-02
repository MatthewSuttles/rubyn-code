# RSpec: Factory Design

## Pattern

Design factories to produce valid records with the minimum possible attributes. Use traits for variations. Use sequences for unique fields. Avoid deeply nested association chains and never put business logic in factories.

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    name { "Jane Doe" }
    role { :user }
    plan { :free }

    trait :admin do
      role { :admin }
      sequence(:email) { |n| "admin#{n}@example.com" }
    end

    trait :pro do
      plan { :pro }
    end

    trait :with_api_key do
      after(:create) do |user|
        create(:api_key, user: user)
      end
    end
  end
end
```

```ruby
# spec/factories/orders.rb
FactoryBot.define do
  factory :order do
    user
    sequence(:reference) { |n| "ORD-#{n.to_s.rjust(6, '0')}" }
    shipping_address { "123 Main St" }
    status { :pending }

    trait :with_line_items do
      transient do
        item_count { 2 }
      end

      after(:create) do |order, evaluator|
        create_list(:line_item, evaluator.item_count, order: order)
        order.reload
      end
    end

    trait :shipped do
      status { :shipped }
      shipped_at { 1.day.ago }
    end

    trait :cancelled do
      status { :cancelled }
      cancelled_at { 1.hour.ago }
    end

    trait :high_value do
      total { 500.00 }
    end
  end
end
```

```ruby
# spec/factories/line_items.rb
FactoryBot.define do
  factory :line_item do
    order
    product
    quantity { 1 }
    unit_price { 10.00 }
  end
end
```

Usage in tests:

```ruby
# Minimal — just what the test needs
user = build_stubbed(:user)
admin = build_stubbed(:user, :admin)
pro_user = create(:user, :pro)

# Compose traits
order = create(:order, :shipped, :high_value)

# Override specific attributes
order = create(:order, total: 99.99, user: user)

# Use transient attributes
order = create(:order, :with_line_items, item_count: 5)
```

## Why This Is Good

- **Minimal by default.** The base factory creates a valid record with nothing extra. Tests that need specific attributes override them explicitly, making dependencies visible.
- **Traits are composable.** `:shipped`, `:cancelled`, `:high_value` can be mixed and matched. No need for separate factories like `shipped_order`, `cancelled_order`, `shipped_high_value_order`.
- **Sequences prevent collisions.** Unique fields use sequences, so tests never fail due to duplicate emails or reference numbers regardless of run order.
- **Transient attributes control association creation.** `item_count: 5` is clearer than creating 5 line items manually. The complexity is in the factory, not in every test.
- **Readable test code.** `create(:order, :shipped, :high_value)` reads like a description of what you need. No setup noise.

## Anti-Pattern

Factories with heavy defaults, deep association chains, and business logic:

```ruby
FactoryBot.define do
  factory :order do
    user
    shipping_address { Faker::Address.full_address }
    billing_address { Faker::Address.full_address }
    status { :pending }
    notes { Faker::Lorem.paragraph }
    reference { "ORD-#{SecureRandom.hex(6)}" }
    currency { "USD" }
    tax_rate { 0.08 }
    discount_code { nil }
    ip_address { Faker::Internet.ip_v4_address }
    user_agent { Faker::Internet.user_agent }

    after(:create) do |order|
      create_list(:line_item, 3, order: order)
      order.update!(
        subtotal: order.line_items.sum(&:total),
        tax: order.line_items.sum(&:total) * 0.08,
        total: order.line_items.sum(&:total) * 1.08
      )
      create(:shipment, order: order)
      create(:payment, order: order, amount: order.total)
      OrderMailer.confirmation(order).deliver_now
    end
  end
end
```

## Why This Is Bad

- **Every `create(:order)` creates 8+ records.** The order, a user, 3 line items, 3 products (via line items), a shipment, and a payment. A test that just needs an order object now waits for 8+ INSERTs.
- **Side effects in factories.** `OrderMailer.confirmation(order).deliver_now` runs in tests. Every test that creates an order sends an email. Tests become slow and flaky.
- **Unnecessary data.** `Faker::Lorem.paragraph` for notes, `Faker::Internet.ip_v4_address` for IP — these slow down factory execution with random generation, and the test almost certainly doesn't care about these values.
- **Hidden coupling.** The factory calculates subtotal, tax, and total. If the calculation logic changes, the factory breaks — or worse, silently produces wrong data that makes tests pass incorrectly.
- **Can't use `build_stubbed`.** Heavy `after(:create)` callbacks mean this factory only works with `create`. You're forced into database hits even for tests that don't need them.

## When To Apply

Always. Every project using FactoryBot should follow these principles from the start:

- **Base factory has required fields only.** If the model validates presence of `email` and `name`, the factory sets `email` and `name`. Nothing else gets a default unless it's required for validity.
- **Use traits for every variation.** Don't add optional fields to the base factory. A shipped order is `create(:order, :shipped)`, not a factory that always sets `shipped_at`.
- **Sequences for every unique field.** Email, reference numbers, slugs, usernames — anything with a uniqueness validation.
- **Transient attributes for controlled association creation.** Don't create associations in the base factory. Use traits like `:with_line_items` that are opt-in.
- **No business logic in factories.** Don't calculate totals, send emails, or trigger service objects. Factories create data — that's it.

## When NOT To Apply

- **Seed data is different from factories.** `db/seeds.rb` can and should create rich, interconnected data for development. That's not a factory — different purpose, different rules.
- **Complex setup for integration/system tests.** System tests may need a fully populated order with line items, shipments, and payments. Use a dedicated factory trait or a setup helper — don't bloat the base factory.

## Edge Cases

**Circular associations:**
If Order belongs_to User and User has_many Orders, the factory chain can loop. Break the cycle by not auto-creating associations in both directions:

```ruby
factory :user do
  # Don't create orders here
end

factory :order do
  user # Creates user, but user factory doesn't create orders
end
```

**Factories for STI (Single Table Inheritance):**
Use inheritance in factories too:

```ruby
factory :notification do
  user
  message { "Something happened" }

  factory :email_notification, class: "EmailNotification" do
    trait :sent do
      sent_at { 1.hour.ago }
    end
  end

  factory :sms_notification, class: "SmsNotification" do
    phone_number { "+15551234567" }
  end
end
```

**Faker vs static values:**
Use static values in factories (`name { "Jane Doe" }`), not Faker (`name { Faker::Name.name }`). Faker adds execution time, produces random data that makes test output inconsistent, and occasionally generates values that fail validations (too long, invalid characters). Save Faker for seed data.

**Association strategy mismatch:**
When using `build_stubbed(:order)`, FactoryBot also stubs the `user` association. But if you `create(:line_item)`, it will `create` (not stub) the associated order. Be deliberate about which strategy you use at each level.
