# Ruby: Concurrency

## Pattern

Ruby has multiple concurrency primitives: Threads for I/O parallelism, Fibers for cooperative concurrency, and Ractors (Ruby 3+) for true parallelism. Choose the right tool for the workload.

### Threads — Best for I/O-Bound Work

```ruby
# Parallel HTTP requests — threads shine here because each waits on I/O
urls = %w[
  https://api.example.com/orders
  https://api.example.com/users
  https://api.example.com/products
]

results = urls.map do |url|
  Thread.new(url) do |u|
    Faraday.get(u).body
  end
end.map(&:value)  # .value blocks until the thread finishes

# Thread pool for controlled concurrency
require "concurrent-ruby"

pool = Concurrent::FixedThreadPool.new(5)
futures = urls.map do |url|
  Concurrent::Future.execute(executor: pool) do
    Faraday.get(url).body
  end
end
results = futures.map(&:value)
```

```ruby
# Thread-safe shared state with Mutex
class Counter
  def initialize
    @count = 0
    @mutex = Mutex.new
  end

  def increment
    @mutex.synchronize { @count += 1 }
  end

  def value
    @mutex.synchronize { @count }
  end
end

counter = Counter.new
threads = 10.times.map do
  Thread.new { 1000.times { counter.increment } }
end
threads.each(&:join)
counter.value  # => 10000 (always correct with Mutex)
```

### concurrent-ruby — Production-Grade Concurrency

```ruby
# Gemfile
gem "concurrent-ruby"
```

```ruby
# Thread-safe data structures
require "concurrent"

# Atomic values — no Mutex needed
counter = Concurrent::AtomicFixnum.new(0)
counter.increment
counter.value  # => 1

# Thread-safe hash
cache = Concurrent::Map.new
cache["key"] = "value"
cache.fetch_or_store("key") { expensive_computation }

# Promises for async pipelines
result = Concurrent::Promise.fulfill("data")
  .then { |data| transform(data) }
  .then { |transformed| save(transformed) }
  .rescue { |error| handle_error(error) }
  .value  # Blocks until chain completes
```

### Fibers — Cooperative Concurrency

```ruby
# Fibers yield control explicitly — useful for generators and coroutines
def id_generator
  Fiber.new do
    id = 0
    loop do
      Fiber.yield(id += 1)
    end
  end
end

gen = id_generator
gen.resume  # => 1
gen.resume  # => 2
gen.resume  # => 3

# Enumerator (built on Fibers) for lazy sequences
def fibonacci
  Enumerator.new do |y|
    a, b = 0, 1
    loop do
      y.yield a
      a, b = b, a + b
    end
  end
end

fibonacci.lazy.select(&:odd?).first(10)
# => [1, 1, 3, 5, 13, 21, 55, 89, 233, 377]
```

### Batch Processing with `in_batches` + Threads

```ruby
# Process large datasets with controlled parallelism
class BatchProcessor
  def initialize(concurrency: 4)
    @pool = Concurrent::FixedThreadPool.new(concurrency)
  end

  def process(scope, batch_size: 100, &block)
    futures = []

    scope.find_in_batches(batch_size: batch_size) do |batch|
      futures << Concurrent::Future.execute(executor: @pool) do
        batch.each { |record| block.call(record) }
      end
    end

    futures.each(&:value!)  # Wait for all, re-raise exceptions
  end

  def shutdown
    @pool.shutdown
    @pool.wait_for_termination(30)
  end
end

# Usage
processor = BatchProcessor.new(concurrency: 4)
processor.process(Order.where(status: :pending)) do |order|
  Orders::ProcessService.call(order)
end
processor.shutdown
```

## Why This Is Good

- **Threads for I/O.** 10 parallel HTTP requests complete in the time of 1 sequential request. Ruby's GVL releases during I/O, enabling true parallelism for network-bound work.
- **`concurrent-ruby` is production-tested.** Thread pools, atomic values, promises, and thread-safe collections — battle-hardened by millions of Ruby apps.
- **Mutex for correctness.** Shared mutable state without a Mutex causes race conditions. With a Mutex, operations are atomic and predictable.
- **Fibers for generators.** Infinite sequences, lazy evaluation, and cooperative multitasking without threads.

## Anti-Pattern

Unprotected shared state or over-threading:

```ruby
# BAD: Race condition — no synchronization
results = []
threads = urls.map do |url|
  Thread.new { results << Faraday.get(url).body }  # Array#<< is NOT thread-safe
end
threads.each(&:join)
# results may be corrupted, missing items, or raise errors

# FIX: Use thread-safe collection or collect from thread return values
results = urls.map do |url|
  Thread.new { Faraday.get(url).body }
end.map(&:value)
```

## When To Apply

- **I/O-bound work** — HTTP requests, file reads, database queries across multiple connections. Threads provide real speedup.
- **Background processing** — Use `concurrent-ruby` thread pools for in-process parallelism.
- **Lazy sequences** — Fibers and Enumerators for infinite or expensive sequences that are consumed incrementally.

## When NOT To Apply

- **CPU-bound work in MRI Ruby.** The Global VM Lock (GVL) prevents true parallel computation. Threads won't speed up math or data processing. Use Ractors or a separate process (via `parallel` gem).
- **Simple sequential code.** If the operation takes 50ms, threading adds overhead without meaningful speedup.
- **Rails request handling.** Puma already manages threads for you. Don't create threads inside controller actions — use background jobs instead.
- **Avoid more than 10-20 threads.** Thread creation and context switching have overhead. Use a fixed thread pool, not unbounded `Thread.new`.
