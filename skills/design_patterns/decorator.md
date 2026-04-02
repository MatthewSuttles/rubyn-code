# Design Pattern: Decorator

## Pattern

Attach additional behavior to an object dynamically by wrapping it in a decorator object. The decorator forwards method calls to the wrapped object and adds behavior before, after, or around the delegation. In Ruby, decorators are often implemented with `SimpleDelegator` or `method_missing`, but explicit delegation is clearest.

```ruby
# Base class — the object to be decorated
class Ai::CompletionClient
  def complete(messages, model:, max_tokens:)
    response = Anthropic::Client.new.messages.create(
      model: model,
      max_tokens: max_tokens,
      messages: messages
    )
    CompletionResult.new(
      content: response.content.first.text,
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens
    )
  end
end

# Decorator: adds logging around the real call
class Ai::LoggingDecorator
  def initialize(client)
    @client = client
  end

  def complete(messages, model:, max_tokens:)
    Rails.logger.info("[AI] Requesting #{model} with #{messages.length} messages")
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    result = @client.complete(messages, model: model, max_tokens: max_tokens)

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    Rails.logger.info("[AI] Completed in #{elapsed.round(2)}s — #{result.input_tokens}in/#{result.output_tokens}out")

    result
  end
end

# Decorator: adds caching
class Ai::CachingDecorator
  def initialize(client, cache: Rails.cache, ttl: 1.hour)
    @client = client
    @cache = cache
    @ttl = ttl
  end

  def complete(messages, model:, max_tokens:)
    cache_key = "ai:#{Digest::SHA256.hexdigest(messages.to_json)}:#{model}"

    @cache.fetch(cache_key, expires_in: @ttl) do
      @client.complete(messages, model: model, max_tokens: max_tokens)
    end
  end
end

# Decorator: adds retry logic
class Ai::RetryDecorator
  def initialize(client, max_retries: 3)
    @client = client
    @max_retries = max_retries
  end

  def complete(messages, model:, max_tokens:)
    retries = 0
    begin
      @client.complete(messages, model: model, max_tokens: max_tokens)
    rescue Faraday::TimeoutError, Faraday::ServerError => e
      retries += 1
      raise if retries > @max_retries
      sleep(2**retries + rand(0.0..0.5))
      retry
    end
  end
end

# Compose decorators — each wraps the previous one
client = Ai::CompletionClient.new
client = Ai::RetryDecorator.new(client)
client = Ai::CachingDecorator.new(client)
client = Ai::LoggingDecorator.new(client)

# The caller sees ONE object with ONE interface
result = client.complete(messages, model: "claude-haiku-4-5-20251001", max_tokens: 4096)
# Logs → checks cache → retries on failure → calls Anthropic
```

Using `SimpleDelegator` for view decorators (presenters):

```ruby
class OrderPresenter < SimpleDelegator
  def formatted_total
    "$#{format('%.2f', total)}"
  end

  def status_badge
    case status
    when "pending" then '<span class="badge bg-warning">Pending</span>'
    when "shipped" then '<span class="badge bg-info">Shipped</span>'
    when "delivered" then '<span class="badge bg-success">Delivered</span>'
    else '<span class="badge bg-secondary">Unknown</span>'
    end.html_safe
  end

  def created_at_formatted
    created_at.strftime("%B %d, %Y at %I:%M %p")
  end
end

# Usage in controller
@order = OrderPresenter.new(Order.find(params[:id]))

# In the view, all Order methods work plus the presenter methods
<%= @order.formatted_total %>
<%= @order.status_badge %>
<%= @order.user.name %>  <!-- delegated to the real Order -->
```

## Why This Is Good

- **Composable behaviors.** Logging, caching, and retry are separate concerns, each in its own class. You compose them like LEGO — add or remove as needed.
- **Same interface throughout.** Every decorator responds to `complete(messages, model:, max_tokens:)`. The caller doesn't know or care how many decorators are stacked.
- **Open/Closed compliant.** Adding rate limiting means writing a `RateLimitDecorator` — not modifying the client, the logger, or the cache.
- **Testable in isolation.** Test `RetryDecorator` by wrapping a fake client that fails twice then succeeds. No real HTTP, no logging, no caching involved.
- **Presenters keep views clean.** `@order.formatted_total` is cleaner than `number_to_currency(@order.total)` scattered across 10 views.

## Anti-Pattern

Putting all cross-cutting concerns inside the base class:

```ruby
class Ai::CompletionClient
  def complete(messages, model:, max_tokens:)
    cache_key = "ai:#{Digest::SHA256.hexdigest(messages.to_json)}"
    cached = Rails.cache.read(cache_key)
    return cached if cached

    Rails.logger.info("[AI] Requesting #{model}")
    start = Time.now

    retries = 0
    begin
      response = Anthropic::Client.new.messages.create(
        model: model, max_tokens: max_tokens, messages: messages
      )
    rescue Faraday::TimeoutError
      retries += 1
      retry if retries <= 3
      raise
    end

    elapsed = Time.now - start
    Rails.logger.info("[AI] Completed in #{elapsed}s")

    result = CompletionResult.new(content: response.content.first.text)
    Rails.cache.write(cache_key, result, expires_in: 1.hour)
    result
  end
end
```

## Why This Is Bad

- **One 30-line method with 4 responsibilities.** API call, logging, caching, and retry are tangled together. Modifying retry logic means reading through cache and logging code.
- **Can't disable caching for tests.** The cache is hardcoded. Tests either hit the cache (stale results) or need `Rails.cache.clear` before every test.
- **Can't reuse retry logic.** If the embedding client also needs retry, you duplicate the retry block. With a decorator, `RetryDecorator.new(embedding_client)` reuses it.

## When To Apply

- **Cross-cutting concerns** — logging, caching, retry, rate limiting, metrics, authentication wrapping. Each is a decorator.
- **View presentation logic** — formatting dates, currencies, status badges, display names. Use `SimpleDelegator` presenters.
- **Feature toggles** — a decorator that conditionally enables new behavior while forwarding to the old behavior by default.
- **API response transformation** — a decorator that normalizes different API response formats into a consistent internal structure.

## When NOT To Apply

- **One behavior that won't be reused.** If only the AI client needs retry logic and nothing else ever will, putting retry inline is simpler than a decorator class.
- **Deep stacks obscure behavior.** If you stack 7 decorators, debugging which one modified the response is difficult. Keep stacks to 3-4 max.
- **Don't decorate ActiveRecord models for persistence logic.** Use service objects. Decorators are for presentation and cross-cutting concerns, not business logic.

## Edge Cases

**`Module#prepend` as an inline decorator:**

```ruby
module Logging
  def complete(messages, model:, max_tokens:)
    Rails.logger.info("[AI] Requesting #{model}")
    result = super
    Rails.logger.info("[AI] Done: #{result.input_tokens} tokens")
    result
  end
end

Ai::CompletionClient.prepend(Logging)
```

This is Ruby's most concise decorator pattern but less flexible — it modifies the class globally rather than per-instance.

**Draper gem for view decorators:**
If the team uses Draper, follow its conventions. Otherwise, `SimpleDelegator` is lighter and framework-free.
