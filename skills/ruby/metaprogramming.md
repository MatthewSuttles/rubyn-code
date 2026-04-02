# Ruby: Metaprogramming

## Pattern

Metaprogramming is writing code that writes code at runtime. Ruby is famous for it — `attr_accessor`, `has_many`, `validates`, and `scope` are all metaprogramming. Use it sparingly and intentionally: to eliminate repetition in DSLs and frameworks, never to be clever.

### Safe Metaprogramming: `define_method`

```ruby
# Generating similar methods from data
class Order < ApplicationRecord
  # Instead of writing 5 nearly identical methods:
  %w[pending confirmed shipped delivered cancelled].each do |status|
    define_method("#{status}?") do
      self.status == status
    end

    define_method("mark_#{status}!") do
      update!(status: status, "#{status}_at": Time.current)
    end
  end
end

# Usage — these methods exist as if hand-written
order.pending?          # true/false
order.mark_confirmed!   # updates status and confirmed_at
```

### Safe Metaprogramming: `class_attribute` and Class Macros

```ruby
# A class macro like Rails' has_many or validates
module HasCreditCost
  extend ActiveSupport::Concern

  class_methods do
    def credit_cost(amount = nil, &block)
      if block
        define_method(:credit_cost) { instance_exec(&block) }
      else
        define_method(:credit_cost) { amount }
      end
    end
  end
end

class Ai::RefactorService
  include HasCreditCost
  credit_cost 2
end

class Ai::ReviewService
  include HasCreditCost
  credit_cost { file_content.length > 5000 ? 3 : 1 }  # Dynamic cost
end

# Usage
Ai::RefactorService.new.credit_cost  # => 2
Ai::ReviewService.new.credit_cost    # => 1 or 3 depending on content
```

### Safe Metaprogramming: `method_missing` with `respond_to_missing?`

```ruby
# Configuration object with dynamic attribute access
class Settings
  def initialize(hash)
    @data = hash.transform_keys(&:to_s)
  end

  def method_missing(name, *args)
    key = name.to_s
    if @data.key?(key)
      value = @data[key]
      value.is_a?(Hash) ? Settings.new(value) : value
    else
      super  # CRITICAL: call super for unknown methods
    end
  end

  def respond_to_missing?(name, include_private = false)
    @data.key?(name.to_s) || super  # CRITICAL: implement this
  end

  def to_h
    @data
  end
end

settings = Settings.new(
  database: { host: "localhost", port: 5432 },
  redis: { url: "redis://localhost:6379" }
)

settings.database.host  # => "localhost"
settings.database.port  # => 5432
settings.redis.url      # => "redis://localhost:6379"
settings.unknown_key    # => NoMethodError (falls through to super)
```

## Why This Is Good (When Used Correctly)

- **Eliminates repetitive code.** 5 status methods generated from an array is DRYer and less error-prone than 5 hand-written methods.
- **Enables clean DSLs.** `credit_cost 2` at the class level reads like configuration, not code. ActiveRecord's `validates :name, presence: true` is the same pattern.
- **Dynamic attribute access.** `settings.database.host` is more readable than `settings.dig("database", "host")` for deeply nested configs.

## Anti-Pattern

Using metaprogramming to be clever, to avoid typing, or where plain Ruby would be clearer:

```ruby
# BAD: Metaprogramming where a simple method would do
class User
  %i[name email phone].each do |attr|
    define_method("display_#{attr}") do
      value = send(attr)
      value.present? ? value : "N/A"
    end
  end
end

# BETTER: Just write the methods
class User
  def display_name = name.presence || "N/A"
  def display_email = email.presence || "N/A"
  def display_phone = phone.presence || "N/A"
end
# 3 lines, immediately readable, greppable, no metaprogramming needed
```

```ruby
# BAD: method_missing without respond_to_missing?
class MagicHash
  def method_missing(name, *args)
    @data[name.to_s]  # Everything silently returns nil for unknown keys
  end
  # Missing respond_to_missing? means is_a?, respond_to?, and inspect lie
end

# BAD: eval with user input (security vulnerability)
def dynamic_call(method_name, *args)
  eval("object.#{method_name}(#{args.join(',')})")  # NEVER do this
end

# SAFE: Use public_send instead
def dynamic_call(object, method_name, *args)
  object.public_send(method_name, *args)
end
```

## Rules for Safe Metaprogramming

1. **Always implement `respond_to_missing?`** when you implement `method_missing`. Otherwise `respond_to?`, `method`, and debugging tools lie.
2. **Always call `super`** in `method_missing` for methods you don't handle. Otherwise all `NoMethodError`s are silently swallowed.
3. **Never use `eval` with dynamic input.** Use `define_method`, `public_send`, or `const_get` instead. `eval` is a security hole.
4. **Prefer `public_send` over `send`.** `send` bypasses `private` — use `public_send` to respect visibility.
5. **Generate methods at load time, not call time.** `define_method` in the class body runs once. `method_missing` runs on every call and is slower.
6. **If the generated methods would be fewer than 5, just write them by hand.** Metaprogramming for 3 methods adds complexity that's not worth the 2 lines saved.

## When To Apply

- **Framework/library DSLs.** If you're building a gem that others configure (`has_many`, `validates`, `scope`), metaprogramming creates clean APIs.
- **Code generation from data.** Generating methods from a list of statuses, roles, or feature flags.
- **When you'd otherwise write 10+ identical methods.** At that point, a loop with `define_method` is legitimately DRYer and safer.

## When NOT To Apply

- **Application code.** Business logic should be explicit, greppable, and debuggable. Metaprogramming makes all three harder.
- **When plain Ruby works.** If you can write 3-5 simple methods instead of metaprogramming, do it. Readable > clever.
- **Fewer than 5 repetitions.** The Rule of Three applies: don't abstract (or metaprogram) until you have enough examples to justify it.
