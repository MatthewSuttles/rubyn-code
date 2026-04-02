# Rails: Logging and Instrumentation

## Pattern

Use structured logging for production observability, `ActiveSupport::Notifications` for custom instrumentation, and tagged logging for request-scoped context. Logs should answer: what happened, when, to whom, and how long it took.

### Structured Logging with Lograge

```ruby
# Gemfile
gem "lograge"

# config/environments/production.rb
config.lograge.enabled = true
config.lograge.formatter = Lograge::Formatters::Json.new

config.lograge.custom_options = lambda do |event|
  {
    user_id: event.payload[:user_id],
    request_id: event.payload[:request_id],
    ip: event.payload[:ip],
    credits_used: event.payload[:credits_used]
  }.compact
end

config.lograge.custom_payload do |controller|
  {
    user_id: controller.current_user&.id,
    request_id: controller.request.request_id,
    ip: controller.request.remote_ip
  }
end

# Output per request:
# {"method":"POST","path":"/api/v1/ai/refactor","format":"json","controller":"Api::V1::Ai::RefactorController",
#  "action":"create","status":200,"duration":1245.3,"user_id":42,"request_id":"abc-123","credits_used":3}
```

### Tagged Logging

```ruby
# config/application.rb
config.log_tags = [:request_id]  # Adds request ID to every log line

# Custom tags
config.log_tags = [
  :request_id,
  ->(request) { "user:#{request.cookie_jar.signed[:user_id]}" }
]

# Manual tagging in services
Rails.logger.tagged("OrderService", "user:#{user.id}") do
  Rails.logger.info("Creating order")
  Rails.logger.info("Order created: #{order.id}")
end
# [abc-123] [OrderService] [user:42] Creating order
# [abc-123] [OrderService] [user:42] Order created: 17
```

### Log Levels Done Right

```ruby
class Ai::CompletionService
  def call(prompt, context:)
    # DEBUG: Detailed info for development troubleshooting — never in production
    Rails.logger.debug { "Prompt tokens estimate: #{estimate_tokens(prompt)}" }

    # INFO: Normal operations that are useful for monitoring
    Rails.logger.info("[AI] Request started model=#{@model} user=#{@user.id}")

    response = @client.complete(messages, model: @model, max_tokens: 4096)

    # INFO: Successful completion with metrics
    Rails.logger.info(
      "[AI] Request completed model=#{@model} " \
      "input_tokens=#{response.input_tokens} output_tokens=#{response.output_tokens} " \
      "duration_ms=#{elapsed_ms} cache_hit=#{response.cache_read_tokens > 0}"
    )

    response
  rescue Faraday::TimeoutError => e
    # WARN: Recoverable problem — retrying or degraded behavior
    Rails.logger.warn("[AI] Timeout after #{elapsed_ms}ms, retrying (attempt #{retries}/3)")
    retry if (retries += 1) <= 3
    raise
  rescue Anthropic::ApiError => e
    # ERROR: Failure that needs attention but isn't crashing the app
    Rails.logger.error("[AI] API error status=#{e.status} message=#{e.message} user=#{@user.id}")
    raise
  rescue StandardError => e
    # FATAL: Unexpected failure — something is seriously wrong
    Rails.logger.fatal("[AI] Unexpected error: #{e.class}: #{e.message}")
    Rails.logger.fatal(e.backtrace.first(10).join("\n"))
    raise
  end
end
```

### Custom Instrumentation with ActiveSupport::Notifications

```ruby
# Publishing events
class Credits::DeductionService
  def call(user, credits)
    ActiveSupport::Notifications.instrument("credits.deducted", {
      user_id: user.id,
      credits: credits,
      balance_after: user.credit_balance - credits
    }) do
      user.deduct_credits!(credits)
    end
  end
end

# Subscribing to events
# config/initializers/instrumentation.rb
ActiveSupport::Notifications.subscribe("credits.deducted") do |name, start, finish, id, payload|
  duration = (finish - start) * 1000
  Rails.logger.info(
    "[Credits] Deducted #{payload[:credits]} from user=#{payload[:user_id]} " \
    "balance=#{payload[:balance_after]} duration=#{duration.round(1)}ms"
  )
end

ActiveSupport::Notifications.subscribe("credits.deducted") do |*, payload|
  StatsD.increment("credits.deducted", tags: ["user:#{payload[:user_id]}"])
  StatsD.gauge("credits.balance", payload[:balance_after], tags: ["user:#{payload[:user_id]}"])
end

# Subscribe to Rails built-in events
ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
  if payload[:duration] > 100  # Log slow queries
    Rails.logger.warn("[SlowQuery] #{payload[:duration].round(1)}ms: #{payload[:sql]}")
  end
end

ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*, payload|
  if payload[:duration] > 1000  # Log slow requests
    Rails.logger.warn("[SlowRequest] #{payload[:path]} #{payload[:duration].round(0)}ms")
  end
end
```

### What to Log (and What Not To)

```ruby
# GOOD: Structured, searchable, useful
Rails.logger.info("[Orders::Create] Created order=#{order.id} user=#{user.id} total=#{order.total} items=#{order.line_items.count}")

# GOOD: Error with context
Rails.logger.error("[Payments] Charge failed user=#{user.id} amount=#{amount} error=#{e.message}")

# BAD: Unstructured, unsearchable
Rails.logger.info("Order created successfully!")
Rails.logger.info("Something went wrong: #{e}")

# BAD: Logging sensitive data
Rails.logger.info("User signed in with password: #{params[:password]}")
Rails.logger.info("API key used: #{api_key}")
Rails.logger.info("Credit card: #{card_number}")

# BAD: Logging entire objects (huge, contains sensitive fields)
Rails.logger.info("User: #{user.inspect}")
Rails.logger.info("Params: #{params.inspect}")

# GOOD: Log only what you need
Rails.logger.info("[Auth] Sign in user=#{user.id} email=#{user.email} ip=#{request.remote_ip}")
```

## Why This Is Good

- **Structured logs are searchable.** `user=42 model=haiku duration_ms=345` can be filtered and aggregated in any log platform (Datadog, Papertrail, CloudWatch). "Order created successfully!" can't.
- **Tagged logging adds context automatically.** Every log line in a request includes the request ID and user ID — no manual threading of context.
- **`ActiveSupport::Notifications` decouples events from reactions.** The service publishes "credits deducted." Logging subscribes. Metrics subscribes. Alerting subscribes. The service doesn't know about any of them.
- **Log levels filter noise.** Production runs at `:info`. Development runs at `:debug`. Slow query warnings are `:warn` — they're visible in production without drowning in debug noise.

## Anti-Pattern

```ruby
# BAD: puts in production code
puts "Order created"

# BAD: p for debugging left in committed code
p user.attributes

# BAD: Logging inside a loop (10,000 log lines for 10,000 records)
users.each { |u| Rails.logger.info("Processing user #{u.id}") }

# BETTER: Log the batch
Rails.logger.info("[BatchProcess] Processing #{users.count} users")
```

## When To Apply

- **Every service object** should log entry, exit, and errors with structured key=value pairs.
- **Lograge in production** — always. Default Rails logging is verbose and unstructured.
- **`ActiveSupport::Notifications`** for cross-cutting metrics (slow queries, credit usage, API latency).
- **Never log passwords, API keys, tokens, or PII.**
