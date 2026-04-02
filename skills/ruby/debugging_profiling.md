# Ruby: Debugging and Profiling

## Pattern

Use the right debugging tool for the problem: `debug` gem (Ruby 3.1+ built-in) for interactive debugging, logging for production visibility, and profiling tools to find performance bottlenecks.

### Interactive Debugging (debug gem)

```ruby
# Ruby 3.1+ has `debug` built in — no gem needed
# Add a breakpoint anywhere:
def create_order(params)
  order = Order.new(params)
  binding.break  # Execution pauses here — inspect variables, step through code
  order.save!
  order
end

# Or use the shorter form
def process(data)
  debugger  # Same as binding.break
  transform(data)
end
```

Debug session commands:
```
# In the debug console:
(rdbg) p order           # Print variable
(rdbg) pp order.errors   # Pretty-print
(rdbg) n                 # Next line (step over)
(rdbg) s                 # Step into method
(rdbg) c                 # Continue execution
(rdbg) info locals       # Show all local variables
(rdbg) bt                # Backtrace
(rdbg) watch @total      # Break when @total changes
(rdbg) break Order#save  # Break when Order#save is called
```

### Pry (Popular Alternative)

```ruby
# Gemfile
gem "pry", group: [:development, :test]
gem "pry-byebug", group: [:development, :test]  # Adds step/next/continue

# Usage
def calculate_total(items)
  subtotal = items.sum(&:price)
  binding.pry  # Drops into Pry REPL
  subtotal * 1.08
end

# Pry commands:
# ls object       — list methods
# cd object       — change context into object
# show-method     — show source code of a method
# whereami        — show current location
# next/step/continue — navigation (with pry-byebug)
```

### Logging Best Practices

```ruby
# Rails logger levels: debug < info < warn < error < fatal
class Orders::CreateService
  def call(params, user)
    Rails.logger.info("[Orders::CreateService] Starting for user=#{user.id}")

    order = user.orders.build(params)
    unless order.valid?
      Rails.logger.warn("[Orders::CreateService] Validation failed: #{order.errors.full_messages}")
      return Result.failure(order.errors)
    end

    order.save!
    Rails.logger.info("[Orders::CreateService] Created order=#{order.id} total=#{order.total}")

    Result.success(order)
  rescue StandardError => e
    Rails.logger.error("[Orders::CreateService] Failed: #{e.class}: #{e.message}")
    Rails.logger.debug(e.backtrace.first(10).join("\n"))
    raise
  end
end

# Tagged logging — adds context to every log line
Rails.logger = ActiveSupport::TaggedLogging.new(Logger.new($stdout))
Rails.logger.tagged("OrderService", "user:#{user.id}") do
  Rails.logger.info("Processing order")
  # => [OrderService] [user:42] Processing order
end

# Structured logging for production (JSON)
# Gemfile
gem "lograge"

# config/environments/production.rb
config.lograge.enabled = true
config.lograge.formatter = Lograge::Formatters::Json.new
config.lograge.custom_payload do |controller|
  { user_id: controller.current_user&.id }
end
# Output: {"method":"POST","path":"/orders","status":201,"duration":45.2,"user_id":42}
```

### Performance Profiling

```ruby
# Benchmark a block
require "benchmark"

time = Benchmark.measure do
  Order.where(status: :pending).find_each { |o| process(o) }
end
puts time  # => 0.120000   0.030000   0.150000 (  0.152345)

# Compare approaches
Benchmark.bm(20) do |x|
  x.report("find_each:") { Order.pending.find_each { |o| o.total } }
  x.report("pluck:") { Order.pending.pluck(:total) }
  x.report("in_batches:") { Order.pending.in_batches.each_record { |o| o.total } }
end

# Memory profiling
# Gemfile
gem "memory_profiler", group: :development

report = MemoryProfiler.report do
  users = User.all.to_a
  users.map(&:email)
end
report.pretty_print
# Shows: allocated memory, retained memory, allocation by gem/file/location

# rack-mini-profiler for web requests
# Gemfile
gem "rack-mini-profiler", group: :development

# Shows a speed badge on every page with:
# - Total request time
# - SQL query count and time
# - Memory usage
# - Flamegraph link
```

### Finding N+1 Queries

```ruby
# Bullet gem detects N+1 in development
# Gemfile
gem "bullet", group: :development

# config/environments/development.rb
config.after_initialize do
  Bullet.enable = true
  Bullet.alert = true          # Browser popup
  Bullet.rails_logger = true   # Log to Rails log
  Bullet.add_footer = true     # Badge in page footer
end

# strict_loading (Rails 6.1+) — raises on lazy loading
class Order < ApplicationRecord
  self.strict_loading_by_default = true
end

# Or per-query
Order.strict_loading.includes(:line_items).each do |order|
  order.line_items  # Works — preloaded
  order.user        # Raises! Not preloaded
end
```

### Production Debugging

```ruby
# Rails console in production
# RAILS_ENV=production rails console

# Safe read-only queries
ActiveRecord::Base.connected_to(role: :reading) do
  Order.where(status: :pending).count
end

# Sandbox mode — rolls back all changes on exit
# rails console --sandbox

# Quick diagnostics
Rails.logger.level = :debug  # Temporarily increase verbosity
ActiveRecord::Base.logger = Logger.new($stdout)  # See all SQL
```

## When To Apply

- **`debugger`/`binding.pry` for investigation.** When you don't understand why code behaves a certain way, stop execution and inspect state.
- **Logging for production.** Always log: service entry/exit, errors with context, and performance metrics. Never log: passwords, API keys, or PII.
- **Profiling before optimizing.** Measure first. The bottleneck is almost never where you think it is.
- **Bullet/strict_loading in development.** Catch N+1s before they reach production.

## When NOT To Apply

- **Don't leave `debugger` calls in committed code.** Use `binding.pry` and `debugger` for local debugging only. CI should catch any that slip through.
- **Don't log everything.** Debug-level logging for every method call creates noise. Log at the right level: info for normal flow, warn for recoverable issues, error for failures.
- **Don't optimize without profiling.** "I think this is slow" → profile it → optimize the actual bottleneck.
