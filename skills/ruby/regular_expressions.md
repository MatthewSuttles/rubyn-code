# Ruby: Regular Expressions

## Pattern

Use regex for pattern matching, validation, and extraction — but prefer string methods when they suffice. Keep patterns readable with `x` flag for complex expressions, and use named captures for clarity.

### Matching

```ruby
# match? — boolean check, fastest (no MatchData allocation)
"ORD-12345".match?(/\AORD-\d+\z/)  # => true
"hello@example.com".match?(URI::MailTo::EMAIL_REGEXP)  # => true

# =~ — returns index of match or nil
"hello world" =~ /world/  # => 6
"hello world" =~ /xyz/    # => nil

# match — returns MatchData object (for captures)
md = "ORD-12345".match(/\AORD-(\d+)\z/)
md[1]  # => "12345"

# String#scan — find all matches
"Order ORD-001 and ORD-002 shipped".scan(/ORD-\d+/)
# => ["ORD-001", "ORD-002"]
```

### Named Captures

```ruby
# Named captures make regex self-documenting
pattern = /\A(?<prefix>ORD|INV)-(?<number>\d{6})-(?<year>\d{4})\z/
md = "ORD-000042-2026".match(pattern)
md[:prefix]  # => "ORD"
md[:number]  # => "000042"
md[:year]    # => "2026"

# Ruby 3.2+ pattern matching with regex
case "ORD-000042-2026"
in /\AORD-(?<number>\d+)/ => ref
  puts "Order #{ref}"
end

# Named captures assigned to local variables (magic behavior)
if /\A(?<name>\w+)@(?<domain>\w+\.\w+)\z/ =~ "alice@example.com"
  puts name    # => "alice"
  puts domain  # => "example.com"
end
```

### Common Patterns

```ruby
# Email (use URI::MailTo::EMAIL_REGEXP instead of writing your own)
URI::MailTo::EMAIL_REGEXP

# UUID
/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

# Phone (loose US format)
/\A\+?1?\d{10}\z/

# Semantic version
/\A(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)(?:-(?<pre>[a-zA-Z0-9.]+))?\z/

# IP address (v4, loose)
/\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/
# Better: Use IPAddr.new(str) and rescue — regex doesn't validate 0-255 range

# Slug (URL-safe)
/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
```

### Verbose Mode for Complex Patterns

```ruby
# x flag — whitespace and comments ignored, dramatically more readable
CREDIT_CARD = /\A
  (?<type>
    4\d{12}(?:\d{3})?        # Visa: starts with 4, 13 or 16 digits
    | 5[1-5]\d{14}           # Mastercard: starts with 51-55, 16 digits
    | 3[47]\d{13}            # Amex: starts with 34 or 37, 15 digits
    | 6(?:011|5\d{2})\d{12}  # Discover: starts with 6011 or 65, 16 digits
  )
\z/x

# Without x flag — unreadable
CREDIT_CARD_UGLY = /\A(?:4\d{12}(?:\d{3})?|5[1-5]\d{14}|3[47]\d{13}|6(?:011|5\d{2})\d{12})\z/
```

### Substitution

```ruby
# sub — first occurrence
"hello world world".sub(/world/, "Ruby")  # => "hello Ruby world"

# gsub — all occurrences
"hello world world".gsub(/world/, "Ruby")  # => "hello Ruby Ruby"

# gsub with block
"ORD-001 and ORD-002".gsub(/ORD-(\d+)/) { |match| "Order ##{$1}" }
# => "Order #001 and Order #002"

# gsub with hash
"cat and dog".gsub(/cat|dog/, "cat" => "feline", "dog" => "canine")
# => "feline and canine"

# Remove matching content
"Hello, World!".gsub(/[^a-zA-Z ]/, "")  # => "Hello World"
```

### Performance

```ruby
# Compile regex once with a constant — don't rebuild per call
EMAIL_PATTERN = /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i.freeze

# BAD: Regex rebuilt on every call
def valid_email?(email)
  email.match?(/\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i)
end

# GOOD: Regex compiled once
def valid_email?(email)
  email.match?(EMAIL_PATTERN)
end

# Prefer match? over =~ when you don't need captures
"test".match?(/\d/)  # Fastest — no MatchData allocated
"test" =~ /\d/       # Slower — allocates MatchData
"test".match(/\d/)   # Slowest — allocates MatchData object
```

## Why This Is Good

- **`match?` is fastest.** When you only need true/false, `match?` avoids allocating a MatchData object — 2-3x faster than `=~`.
- **Named captures are self-documenting.** `md[:year]` is clearer than `md[3]`. The reader doesn't need to count capture groups.
- **Verbose mode (`x`) makes complex patterns readable.** Comments explain each part. Whitespace groups related sections.
- **Constants avoid recompilation.** A regex literal in a method body is recompiled on every call. A frozen constant is compiled once.

## Anti-Pattern

```ruby
# BAD: Regex where a string method would do
email.match?(/example\.com/) 
email.include?("example.com")   # Simpler, faster, clearer

"hello world".match?(/\Ahello/)
"hello world".start_with?("hello")  # No regex needed

name.gsub(/\s+/, " ")
name.squeeze(" ")  # Collapses repeated spaces without regex
```

## When To Apply

- **Pattern validation** — emails, phone numbers, UUIDs, reference formats.
- **Extraction** — pulling structured data from strings (log parsing, URL matching).
- **Complex substitution** — replacing patterns with computed values.
- **Named captures** — whenever you have 2+ capture groups.

## When NOT To Apply

- **Simple string checks.** `include?`, `start_with?`, `end_with?`, `==` are clearer and faster than regex for exact matches.
- **HTML/XML parsing.** Use Nokogiri, not regex. Regex can't handle nested structures.
- **Email validation in production.** Use `URI::MailTo::EMAIL_REGEXP` or better yet, just send a confirmation email — that's the real validation.
- **Complex parsing.** If the regex exceeds 3 lines even in verbose mode, consider a proper parser (StringScanner, Parslet, or a state machine).
