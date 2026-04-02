# Gems: Redis

## Pattern

Use Redis for caching, rate limiting, sessions, job queues, and real-time features. Use `connection_pool` for thread-safe access. Keep data ephemeral — Redis is a cache, not a database.

### Setup

```ruby
# Gemfile
gem "redis", "~> 5.0"
gem "connection_pool", "~> 2.4"
gem "hiredis-client"  # C extension for faster Redis — optional but recommended

# config/initializers/redis.rb
REDIS_POOL = ConnectionPool.new(size: ENV.fetch("REDIS_POOL_SIZE", 10).to_i, timeout: 5) do
  Redis.new(
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"),
    timeout: 2,
    reconnect_attempts: 3
  )
end

# Usage — always check out from pool, never hold a connection
REDIS_POOL.with do |redis|
  redis.set("key", "value", ex: 3600)  # Expires in 1 hour
  value = redis.get("key")
end
```

### Caching

```ruby
# Rails cache store
# config/environments/production.rb
config.cache_store = :redis_cache_store, {
  url: ENV.fetch("REDIS_URL"),
  expires_in: 1.hour,
  namespace: "rubyn:cache",
  pool_size: ENV.fetch("REDIS_POOL_SIZE", 10).to_i,
  error_handler: ->(method:, returning:, exception:) {
    Rails.logger.error("Redis cache error: #{method} #{exception.message}")
    Sentry.capture_exception(exception) if defined?(Sentry)
  }
}

# Usage via Rails.cache
Rails.cache.fetch("user:#{user.id}:credits", expires_in: 5.minutes) do
  user.credit_ledger_entries.sum(:amount)  # Only computed on cache miss
end

Rails.cache.delete("user:#{user.id}:credits")  # Invalidate
Rails.cache.delete_matched("user:#{user.id}:*")  # Invalidate all user caches
```

### Rate Limiting

```ruby
# Simple sliding window rate limiter
class RateLimiter
  def initialize(pool: REDIS_POOL)
    @pool = pool
  end

  def allowed?(key, limit:, period:)
    @pool.with do |redis|
      current = redis.get(key).to_i
      return true if current < limit

      false
    end
  end

  def increment(key, period:)
    @pool.with do |redis|
      count = redis.incr(key)
      redis.expire(key, period) if count == 1  # Set TTL on first increment
      count
    end
  end

  def remaining(key, limit:)
    @pool.with do |redis|
      current = redis.get(key).to_i
      [limit - current, 0].max
    end
  end
end

# Usage in middleware or controller
limiter = RateLimiter.new
key = "rate:#{current_user.id}:#{Time.current.beginning_of_minute.to_i}"

unless limiter.allowed?(key, limit: 60, period: 60)
  render json: { error: "Rate limited" }, status: :too_many_requests
  return
end

limiter.increment(key, period: 60)
```

### Distributed Locks

```ruby
# Prevent concurrent execution of the same job
class DistributedLock
  def initialize(pool: REDIS_POOL)
    @pool = pool
  end

  def with_lock(key, ttl: 30, &block)
    token = SecureRandom.hex(16)

    @pool.with do |redis|
      acquired = redis.set("lock:#{key}", token, nx: true, ex: ttl)
      raise LockNotAcquired, "Could not acquire lock: #{key}" unless acquired

      begin
        yield
      ensure
        # Only release if we still own the lock (compare token)
        release_script = <<~LUA
          if redis.call("get", KEYS[1]) == ARGV[1] then
            return redis.call("del", KEYS[1])
          else
            return 0
          end
        LUA
        redis.eval(release_script, keys: ["lock:#{key}"], argv: [token])
      end
    end
  end
end

# Usage
lock = DistributedLock.new
lock.with_lock("index:project:#{project.id}", ttl: 60) do
  Embeddings::CodebaseIndexer.call(project)
end
```

### Pub/Sub for Real-Time

```ruby
# Publishing events
REDIS_POOL.with do |redis|
  redis.publish("order:updates", { order_id: order.id, status: "shipped" }.to_json)
end

# Subscribing (in a dedicated thread or process)
Thread.new do
  Redis.new(url: ENV["REDIS_URL"]).subscribe("order:updates") do |on|
    on.message do |channel, message|
      data = JSON.parse(message)
      ActionCable.server.broadcast("order_#{data['order_id']}", data)
    end
  end
end
```

### Key Design

```ruby
# Use namespaced, structured keys
"rubyn:cache:user:42:credits"        # Cache key
"rubyn:rate:user:42:1710892800"      # Rate limit (epoch minute)
"rubyn:lock:index:project:17"        # Distributed lock
"rubyn:session:abc123"               # Session data

# GOOD: Include version for cache invalidation
"rubyn:v2:user:42:dashboard"         # Bump v2→v3 to invalidate all dashboard caches

# GOOD: Include TTL in the key name for debugging
# Not in the key itself — use Redis TTL — but document expected TTLs:
# credits cache: 5 min
# dashboard: 15 min  
# session: 24 hours
# rate limit: 60 seconds
```

## Why This Is Good

- **Connection pool prevents thread contention.** Without a pool, threads fight over a single Redis connection. `ConnectionPool` manages N connections and hands them out safely.
- **Namespaced keys prevent collisions.** `rubyn:cache:` vs `rubyn:rate:` vs `rubyn:lock:` — you can flush caches without losing rate limits.
- **TTLs prevent unbounded growth.** Every key should expire. Redis is memory-bound — keys without TTLs leak memory until OOM.
- **Lua scripts for atomic operations.** The distributed lock release uses a Lua script to atomically check-and-delete. Two separate commands would have a race condition.
- **Error handler on cache store.** If Redis goes down, the app degrades gracefully (cache misses) instead of crashing.

## Anti-Pattern

```ruby
# BAD: Global Redis connection shared across threads
$redis = Redis.new  # NOT thread-safe under load
$redis.get("key")   # Race conditions in multi-threaded Puma

# BAD: No TTL — keys live forever
redis.set("data", value)        # Never expires — memory leak
redis.set("data", value, ex: 3600)  # GOOD: expires in 1 hour

# BAD: No error handling — Redis down crashes the app
value = redis.get("key")  # Redis::ConnectionError crashes the request
# GOOD: Rescue and degrade
value = redis.get("key") rescue nil
```

## When To Apply

- **Caching** — Rails.cache with Redis store. Most common use case.
- **Rate limiting** — API endpoints, login attempts, credit usage.
- **Sidekiq** — already uses Redis for job queues.
- **ActionCable** — WebSocket pub/sub backend.
- **Distributed locks** — prevent duplicate job execution across workers.
- **Session store** — faster than database sessions for high-traffic apps.

## When NOT To Apply

- **Persistent data.** Redis can lose data on restart (unless using AOF/RDB). Don't store data you can't recompute.
- **Large values.** Redis is optimized for small values (<1KB). Don't store 10MB JSON blobs.
- **Complex queries.** Redis is a key-value store, not a database. No JOINs, no WHERE clauses, no full-text search.
