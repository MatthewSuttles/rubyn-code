# Ruby: String Handling

## Pattern

Strings are everywhere in Ruby. Use the right tool: frozen string literals for performance, heredocs for multi-line, interpolation for building, and `String` methods over regex when possible.

### Frozen String Literals

```ruby
# frozen_string_literal: true

# This magic comment at the top of the file freezes ALL string literals
# Frozen strings can't be mutated, which prevents bugs and improves performance
# (Ruby can reuse the same object instead of allocating new ones)

name = "Alice"
name << " Smith"  # => FrozenError: can't modify frozen String

# When you need a mutable string, use .dup or unary +
name = +"Alice"       # Mutable copy
name = "Alice".dup    # Same thing, more explicit
name << " Smith"      # Works

# RECOMMENDATION: Add `# frozen_string_literal: true` to every Ruby file.
# Rubocop enforces this by default. Rails 8 enables it in new apps.
```

### Interpolation vs Concatenation vs Format

```ruby
user = "Alice"
count = 3

# GOOD: Interpolation — clearest for simple cases
"Hello, #{user}! You have #{count} orders."

# GOOD: Format for precise number formatting
format("Total: $%.2f", total / 100.0)       # => "Total: $19.99"
format("Order %06d", order_id)               # => "Order 000042"
format("%s has %d orders", user, count)      # => "Alice has 3 orders"

# BAD: Concatenation — ugly, slow, error-prone with non-strings
"Hello, " + user + "! You have " + count.to_s + " orders."

# BAD: String interpolation for SQL (security vulnerability)
User.where("name = '#{params[:name]}'")     # SQL INJECTION!
User.where("name = ?", params[:name])        # Safe: parameterized
```

### Heredocs

```ruby
# Plain heredoc — preserves indentation literally
sql = <<-SQL
  SELECT *
  FROM orders
  WHERE status = 'pending'
SQL

# Squiggly heredoc (Ruby 2.3+) — strips leading whitespace based on the least-indented line
message = <<~MSG
  Hello #{user.name},

  Your order #{order.reference} has shipped!
  Expected delivery: #{order.estimated_delivery.strftime("%B %d")}.

  Thanks,
  The Rubyn Team
MSG
# Result has no leading spaces — perfect for emails and templates

# Frozen heredoc
QUERY = <<~SQL.freeze
  SELECT users.email, COUNT(orders.id) as order_count
  FROM users
  LEFT JOIN orders ON orders.user_id = users.id
  GROUP BY users.email
SQL
```

### Common String Operations

```ruby
# Presence and blank checks (Rails)
name = "  "
name.blank?     # => true (whitespace only)
name.present?   # => false
name.presence   # => nil (returns nil if blank, self if present)

# Use .presence for conditional assignment
display_name = user.nickname.presence || user.email
# Instead of: user.nickname.blank? ? user.email : user.nickname

# Stripping and squishing
"  hello  world  ".strip       # => "hello  world" (leading/trailing only)
"  hello  world  ".squish      # => "hello world" (Rails — collapses internal whitespace too)

# Case conversion
"hello_world".camelize         # => "HelloWorld" (Rails)
"HelloWorld".underscore        # => "hello_world" (Rails)
"hello world".titleize         # => "Hello World" (Rails)
"HELLO".downcase               # => "hello"
"hello".upcase                 # => "HELLO"

# Checking content
"hello world".include?("world")         # => true
"hello world".start_with?("hello")      # => true
"hello world".end_with?("world")        # => true
"hello world".match?(/\d/)              # => false (no digits)

# Extracting
"user@example.com".split("@")          # => ["user", "example.com"]
"ORD-001-2026".split("-", 2)           # => ["ORD", "001-2026"] (limit splits)
"hello world"[0..4]                     # => "hello"
"order_12345".delete_prefix("order_")   # => "12345" (Ruby 2.5+)
"file.rb".delete_suffix(".rb")          # => "file" (Ruby 2.5+)

# Replacing
"hello world".sub("world", "Ruby")      # => "hello Ruby" (first occurrence)
"aabaa".gsub("a", "x")                  # => "xxbxx" (all occurrences)
"hello world".tr("aeiou", "*")          # => "h*ll* w*rld" (character-level replace)

# Truncation (Rails)
"A very long description that goes on and on".truncate(30)
# => "A very long description tha..."
"A very long description".truncate(20, separator: " ")
# => "A very long..."  (breaks at word boundary)

# Parameterize for URLs (Rails)
"Hello World! It's great.".parameterize  # => "hello-world-it-s-great"
```

### String Building for Performance

```ruby
# BAD: Repeated concatenation (creates new string objects each time)
result = ""
items.each { |item| result += "#{item.name}: #{item.price}\n" }

# GOOD: Array join (one allocation at the end)
result = items.map { |item| "#{item.name}: #{item.price}" }.join("\n")

# GOOD: StringIO for large outputs
require "stringio"
buffer = StringIO.new
items.each { |item| buffer.puts "#{item.name}: #{item.price}" }
result = buffer.string

# GOOD: String interpolation with Array for building
parts = []
parts << "Status: #{order.status}"
parts << "Total: #{order.formatted_total}"
parts << "Items: #{order.line_items.count}" if order.line_items.loaded?
parts.join(" | ")
```

## Why This Is Good

- **Frozen string literals prevent mutation bugs and improve performance.** A frozen string used as a hash key or constant is allocated once and reused.
- **Interpolation is the Ruby way.** `"Hello, #{name}"` is cleaner, safer, and faster than concatenation.
- **Squiggly heredocs keep code clean.** Multi-line strings stay properly indented in the source without extra whitespace in the output.
- **`.presence` eliminates conditional checks.** One method replaces a blank-check ternary.
- **Array + join beats repeated concatenation.** Concatenation creates N intermediate string objects. Join creates one.

## When To Apply

- **`# frozen_string_literal: true`** — every Ruby file, always.
- **Heredocs** — any string longer than 2 lines.
- **`.presence`** — any `x.blank? ? default : x` pattern.
- **`.parameterize`** — any user input going into a URL slug.
- **`format`** — any numeric formatting (currency, percentages, padded numbers).

## When NOT To Apply

- **Don't over-optimize string building.** For 5-10 concatenations, readability wins over performance. `join` matters when you have 1,000+ items.
- **Don't use `.squish` on content that should preserve whitespace** — code blocks, pre-formatted text, etc.
- **Don't freeze mutable strings.** If you're building a string incrementally, don't freeze the initial value.
