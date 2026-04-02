# Ruby: Blocks, Procs, and Lambdas

## Pattern

Blocks are Ruby's most powerful feature — closures that capture their surrounding context and can be passed to methods. Understanding blocks, procs, and lambdas is essential for writing idiomatic Ruby.

### Blocks

```ruby
# A block is code between do/end or { } passed to a method
[1, 2, 3].each { |n| puts n }

[1, 2, 3].each do |n|
  puts n
end

# Convention: { } for single-line, do/end for multi-line

# yield calls the block from inside the method
def with_logging
  Rails.logger.info("Starting")
  result = yield
  Rails.logger.info("Completed")
  result
end

with_logging { Order.create!(params) }

# block_given? checks if a block was passed
def find_or_default(collection, default: nil)
  result = collection.find { |item| yield(item) }
  result || default
end
```

### Blocks for Resource Management

```ruby
# The block pattern guarantees cleanup — Ruby's most important idiom
File.open("data.csv") do |file|
  file.each_line { |line| process(line) }
end
# File is automatically closed when the block exits, even on exception

# Build your own resource-managing methods
class DatabaseConnection
  def self.with_connection
    conn = checkout
    yield conn
  ensure
    checkin(conn)
  end
end

DatabaseConnection.with_connection do |conn|
  conn.execute("SELECT * FROM orders")
end
```

### Procs and Lambdas

```ruby
# Proc: a block saved as an object
doubler = Proc.new { |n| n * 2 }
doubler.call(5)  # => 10
doubler.(5)      # => 10 (shorthand)

# Lambda: a stricter proc (checks arity, return scoping)
doubler = ->(n) { n * 2 }
doubler.call(5)  # => 10

# Symbol-to-proc: converts a method name to a proc
["alice", "bob"].map(&:upcase)  # => ["ALICE", "BOB"]
# Equivalent to: .map { |s| s.upcase }

# Method objects as procs
def double(n) = n * 2
[1, 2, 3].map(&method(:double))  # => [2, 4, 6]
```

### Proc vs Lambda Differences

```ruby
# 1. Arity: Lambda checks argument count, Proc doesn't
my_lambda = ->(a, b) { a + b }
my_lambda.call(1)      # ArgumentError: wrong number of arguments (given 1, expected 2)

my_proc = Proc.new { |a, b| (a || 0) + (b || 0) }
my_proc.call(1)        # => 1 (b is nil, no error)

# 2. Return: Lambda returns to its caller, Proc returns from the enclosing method
def test_lambda
  l = -> { return "from lambda" }
  l.call
  "after lambda"  # This line executes
end
test_lambda  # => "after lambda"

def test_proc
  p = Proc.new { return "from proc" }
  p.call
  "after proc"  # This line NEVER executes
end
test_proc  # => "from proc"

# RULE: Use lambdas. They behave predictably.
```

### Practical Patterns

```ruby
# Strategy via lambda
PRICING = {
  standard: ->(amount) { amount },
  premium: ->(amount) { amount * 0.9 },
  vip: ->(amount) { amount * 0.8 }
}

def calculate_price(amount, tier:)
  PRICING.fetch(tier, PRICING[:standard]).call(amount)
end

# Callbacks / hooks
class Pipeline
  def initialize
    @before_hooks = []
    @after_hooks = []
  end

  def before(&block)
    @before_hooks << block
  end

  def after(&block)
    @after_hooks << block
  end

  def execute(data)
    @before_hooks.each { |hook| hook.call(data) }
    result = yield(data)
    @after_hooks.each { |hook| hook.call(result) }
    result
  end
end

pipeline = Pipeline.new
pipeline.before { |data| puts "Processing: #{data}" }
pipeline.after { |result| puts "Done: #{result}" }
pipeline.execute("order-123") { |data| "Processed #{data}" }

# Filtering with lambdas
active = ->(user) { user.active? }
premium = ->(user) { user.plan == "pro" }
recent = ->(user) { user.created_at > 30.days.ago }

filters = [active, premium, recent]
users.select { |user| filters.all? { |f| f.call(user) } }

# Configuration DSLs
class Router
  def initialize(&block)
    @routes = {}
    instance_eval(&block) if block
  end

  def get(path, &handler)
    @routes[[:get, path]] = handler
  end

  def post(path, &handler)
    @routes[[:post, path]] = handler
  end
end

router = Router.new do
  get "/health" do
    { status: "ok" }
  end

  post "/orders" do
    Order.create!(params)
  end
end
```

## Why This Is Good

- **Blocks enable resource safety.** `File.open { }` guarantees cleanup. `ActiveRecord::Base.transaction { }` guarantees rollback on failure. This is more reliable than try/finally patterns.
- **Lambdas are first-class functions.** Store them in hashes, pass them as arguments, compose them. Ruby's functional programming capabilities are built on lambdas.
- **Symbol-to-proc is concise and expressive.** `.map(&:name)` is instantly readable by any Rubyist. It's not just shorter — it's clearer.
- **DSLs via `instance_eval`.** Blocks with `instance_eval` enable clean configuration DSLs (like Rails routes, RSpec, Sinatra).

## When To Apply

- **Resource management** — always use blocks for open/close, start/stop, begin/end patterns.
- **Callbacks and hooks** — pass blocks to register behavior that runs at specific points.
- **Strategy selection** — lambdas in a hash for lightweight strategies that don't need a full class.
- **Iteration and transformation** — blocks with Enumerable methods are the heart of Ruby.

## When NOT To Apply

- **Complex logic in a block.** If a block is longer than 5-7 lines, extract it into a method or a class. Blocks should be concise.
- **Procs for business logic.** Use lambdas, not procs. Proc's return behavior is surprising and error-prone.
- **Deep `instance_eval` nesting.** More than one level of `instance_eval` becomes hard to reason about. Keep DSLs shallow.
