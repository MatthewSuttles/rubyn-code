# Design Pattern: Proxy

## Pattern

Provide a surrogate or placeholder for another object to control access to it. Proxies add a layer between the client and the real object — for lazy loading, access control, logging, or caching — without the client knowing the difference.

```ruby
# Caching proxy — caches expensive API calls
class CachingEmbeddingProxy
  def initialize(real_client, cache: Rails.cache, ttl: 24.hours)
    @real_client = real_client
    @cache = cache
    @ttl = ttl
  end

  def embed(texts)
    cache_key = "embeddings:#{Digest::SHA256.hexdigest(texts.sort.join('|'))}"

    @cache.fetch(cache_key, expires_in: @ttl) do
      @real_client.embed(texts)
    end
  end

  def embed_query(text)
    # Queries are unique per request — don't cache
    @real_client.embed_query(text)
  end
end

# Usage — caller doesn't know it's a proxy
client = Embeddings::HttpClient.new(base_url: ENV["EMBEDDING_URL"])
client = CachingEmbeddingProxy.new(client)
vectors = client.embed(["class Order; end"])  # Cached after first call
```

```ruby
# Access control proxy — checks permissions before delegating
class AuthorizingProjectProxy
  def initialize(project, user)
    @project = project
    @user = user
    @membership = project.project_memberships.find_by(user: user)
  end

  def code_embeddings
    require_role!(:viewer)
    @project.code_embeddings
  end

  def update!(attributes)
    require_role!(:admin)
    @project.update!(attributes)
  end

  def destroy!
    require_role!(:owner)
    @project.destroy!
  end

  def method_missing(method, ...)
    require_role!(:viewer)
    @project.public_send(method, ...)
  end

  def respond_to_missing?(method, include_private = false)
    @project.respond_to?(method, include_private)
  end

  private

  ROLE_HIERARCHY = { viewer: 0, member: 1, admin: 2, owner: 3 }.freeze

  def require_role!(minimum)
    current = ROLE_HIERARCHY[@membership&.role&.to_sym] || -1
    required = ROLE_HIERARCHY[minimum]

    raise Forbidden, "Requires #{minimum} role" if current < required
  end
end

# Usage
project = AuthorizingProjectProxy.new(project, current_user)
project.code_embeddings   # Works for viewer+
project.update!(name: "New Name")  # Only admin+
project.destroy!           # Only owner
```

```ruby
# Lazy loading proxy — defers expensive initialization
class LazyModelProxy
  def initialize(&loader)
    @loader = loader
    @loaded = false
    @target = nil
  end

  def method_missing(method, ...)
    load_target!
    @target.public_send(method, ...)
  end

  def respond_to_missing?(method, include_private = false)
    load_target!
    @target.respond_to?(method, include_private)
  end

  private

  def load_target!
    unless @loaded
      @target = @loader.call
      @loaded = true
    end
  end
end

# Usage — the DB query only runs when you access the object
expensive_report = LazyModelProxy.new { Report.generate_monthly(Date.current) }
# No query yet...
expensive_report.total  # NOW the query runs
```

## Why This Is Good

- **Transparent to the caller.** The proxy responds to the same methods as the real object. Code that uses the real client works unchanged with the caching proxy.
- **Separation of concerns.** Caching logic lives in the proxy, not in the client. Auth logic lives in the auth proxy, not in the model.
- **Composable with other patterns.** A caching proxy can wrap a logging decorator which wraps the real client. Each layer adds one concern.

## When To Apply

- **Caching expensive operations.** API calls, database queries, computations.
- **Access control.** Check permissions before allowing operations on a resource.
- **Lazy loading.** Defer initialization of expensive objects until they're actually used.
- **Remote objects.** Wrap a remote API to look like a local object.

## When NOT To Apply

- **Simple delegation.** If you're just forwarding calls without adding behavior, use `delegate` or `SimpleDelegator` — not a proxy.
- **Decorator already fits.** Proxies control access. Decorators add behavior. If you're adding behavior (logging, metrics), use a decorator.
- **The object is cheap to create.** Lazy loading a simple `User.new` adds complexity without benefit.
