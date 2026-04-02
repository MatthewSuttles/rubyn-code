# Ruby: Hash Patterns

## Pattern

Hashes are Ruby's most versatile data structure. Use the right access pattern for safety, the right transformation for clarity, and know when a Hash should become an object.

### Safe Access

```ruby
config = { database: { host: "localhost", port: 5432 }, redis: { url: "redis://localhost" } }

# GOOD: dig for nested access — returns nil instead of raising
config.dig(:database, :host)        # => "localhost"
config.dig(:database, :timeout)     # => nil (missing key)
config.dig(:missing, :nested)       # => nil (missing parent)

# GOOD: fetch for required keys — raises if missing, or uses default
ENV.fetch("DATABASE_URL")                        # Raises KeyError if missing
ENV.fetch("OPTIONAL_KEY", "default_value")       # Returns default if missing
ENV.fetch("PORT") { 3000 }                       # Block for computed default

config.fetch(:database)             # Raises if :database doesn't exist
config.fetch(:timeout, 30)          # Returns 30 if :timeout doesn't exist

# BAD: [] silently returns nil — hides bugs
config[:databas][:host]             # NoMethodError: undefined method `[]' for nil
# Typo in :databas goes undetected until runtime crash

# RULE: Use fetch for required keys, dig for optional nested keys, [] only when nil is an acceptable value
```

### Transformation

```ruby
data = { "user_name" => "Alice", "user_email" => "alice@example.com", "role" => "admin" }

# Symbolize keys
data.symbolize_keys                  # => { user_name: "Alice", user_email: "alice@example.com", role: "admin" }
# Rails method — in pure Ruby use: data.transform_keys(&:to_sym)

# Transform keys
data.transform_keys { |k| k.delete_prefix("user_") }
# => { "name" => "Alice", "email" => "alice@example.com", "role" => "admin" }

# Transform values
prices = { widget: 10_00, gadget: 25_00, gizmo: 50_00 }
prices.transform_values { |cents| "$#{format('%.2f', cents / 100.0)}" }
# => { widget: "$10.00", gadget: "$25.00", gizmo: "$50.00" }

# Slice — pick specific keys (Rails, or Ruby 2.5+)
user_params = params.slice(:name, :email, :phone)

# Except — remove specific keys (Rails)
safe_params = params.except(:admin, :role, :password_digest)

# Select / reject by key or value
prices.select { |_, v| v > 20_00 }   # => { gadget: 25_00, gizmo: 50_00 }
prices.reject { |k, _| k == :gizmo } # => { widget: 10_00, gadget: 25_00 }

# Filter map (Ruby 2.7+)
prices.filter_map { |k, v| "#{k}: $#{v / 100.0}" if v > 15_00 }
# => ["gadget: $25.0", "gizmo: $50.0"]
```

### Merging

```ruby
defaults = { timeout: 30, retries: 3, format: :json }
overrides = { timeout: 60, debug: true }

# merge — right side wins on conflicts
config = defaults.merge(overrides)
# => { timeout: 60, retries: 3, format: :json, debug: true }

# merge with block — resolve conflicts custom
counts_a = { orders: 10, users: 5 }
counts_b = { orders: 3, products: 8 }
counts_a.merge(counts_b) { |_key, a, b| a + b }
# => { orders: 13, users: 5, products: 8 }

# Deep merge (Rails) — merges nested hashes recursively
base = { database: { host: "localhost", pool: 5 } }
override = { database: { pool: 10, timeout: 30 } }
base.deep_merge(override)
# => { database: { host: "localhost", pool: 10, timeout: 30 } }

# Reverse merge (Rails) — "fill in defaults" — left side wins
user_options = { theme: "dark" }
user_options.reverse_merge(theme: "light", locale: "en", per_page: 25)
# => { theme: "dark", locale: "en", per_page: 25 }
# User's theme preserved, defaults filled in for missing keys

# With duplicate keys — ** (double splat) syntax
config = { **defaults, **overrides }  # Same as defaults.merge(overrides)
```

### Building Hashes

```ruby
users = [user_a, user_b, user_c]

# index_by (Rails) — build a lookup hash
users_by_id = users.index_by(&:id)
# => { 1 => user_a, 2 => user_b, 3 => user_c }

# group_by — group into arrays by key
users.group_by(&:role)
# => { "admin" => [user_a], "user" => [user_b, user_c] }

# tally (Ruby 2.7+) — count occurrences
%w[pending pending shipped delivered pending].tally
# => { "pending" => 3, "shipped" => 1, "delivered" => 1 }

# each_with_object — build a hash from iteration
users.each_with_object({}) do |user, hash|
  hash[user.email] = user.name
end

# to_h with block (Ruby 2.6+)
users.to_h { |u| [u.id, u.name] }
# => { 1 => "Alice", 2 => "Bob", 3 => "Charlie" }

# zip to build from parallel arrays
keys = [:name, :email, :role]
values = ["Alice", "alice@example.com", "admin"]
keys.zip(values).to_h
# => { name: "Alice", email: "alice@example.com", role: "admin" }
```

### Pattern Matching with Hashes (Ruby 3+)

```ruby
response = { status: 200, body: { user: { name: "Alice", role: "admin" } } }

case response
in { status: 200, body: { user: { role: "admin" } } }
  puts "Admin user response"
in { status: 200, body: { user: { name: String => name } } }
  puts "User: #{name}"
in { status: (400..499) => code }
  puts "Client error: #{code}"
in { status: (500..) }
  puts "Server error"
end

# Destructuring assignment
response => { body: { user: { name: } } }
puts name  # => "Alice"
```

### When a Hash Should Become an Object

```ruby
# SMELL: Hash with known, fixed keys passed around everywhere
def process_order(order_data)
  validate(order_data[:address])
  charge(order_data[:total], order_data[:payment_token])
  notify(order_data[:email])
end

# Accessing order_data[:adress] (typo) returns nil silently

# FIX: Use a Data class or Struct
OrderRequest = Data.define(:address, :total, :payment_token, :email)

def process_order(request)
  validate(request.address)
  charge(request.total, request.payment_token)
  notify(request.email)
end

# OrderRequest.new(adress: "...") → ArgumentError: unknown keyword: adress
# Typos caught at construction time, not buried in runtime nils
```

## Why This Is Good

- **`fetch` fails loudly on missing keys.** A typo in `config[:databse_url]` returns nil silently and crashes somewhere else. `config.fetch(:database_url)` raises immediately at the point of error.
- **`dig` handles nested nils gracefully.** No more `config[:database] && config[:database][:host]` chains. One method call.
- **Transformation methods are functional.** `transform_values`, `select`, `reject` return new hashes without mutating the original.
- **`index_by` and `tally` replace manual loops.** Building a lookup hash or counting occurrences is one method call, not a 4-line `each_with_object`.
- **Pattern matching makes hash destructuring readable.** Complex conditional logic on nested hashes becomes a clean `case/in`.

## When To Apply

- **`fetch` for ENV variables.** Always. `ENV.fetch("API_KEY")` fails at boot if the key is missing, not at runtime when a request fails.
- **`dig` for API responses.** External API responses have unpredictable nesting. `response.dig(:data, :attributes, :name)` is safe.
- **`transform_keys/values` for data normalization.** API responses with string keys, webhook payloads with camelCase — normalize once at the boundary.
- **`to_h` with a block for building lookups.** Cleaner than `each_with_object` for simple key-value mappings.

## When NOT To Apply

- **Don't use `fetch` when nil is a valid value.** If a config key is genuinely optional, use `dig` or `[]` with a nil check.
- **When the hash should be an object.** If you're passing the same hash shape to 3+ methods, it's a Data class or Struct waiting to happen.
- **Don't chain too many transformations.** `hash.symbolize_keys.slice(:a, :b).transform_values(&:to_i).merge(defaults)` — if the chain exceeds 3 steps, break it into named intermediate variables.
