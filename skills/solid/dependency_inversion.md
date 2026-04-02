# SOLID: Dependency Inversion Principle (DIP)

## Pattern

High-level modules should not depend on low-level modules. Both should depend on abstractions. In Ruby, this means: depend on duck-typed interfaces (what an object *does*), not on concrete classes (what an object *is*). Inject dependencies rather than hardcoding them.

```ruby
# GOOD: High-level service depends on an injected abstraction, not a concrete class

class Ai::CompletionService
  # Depends on: any object that responds to .complete(messages, model:, max_tokens:)
  # Does NOT depend on: Anthropic::Client specifically
  def initialize(client:)
    @client = client
  end

  def call(prompt, context:)
    messages = build_messages(prompt, context)
    response = @client.complete(messages, model: "claude-haiku-4-5-20251001", max_tokens: 4096)

    Result.new(
      content: response.content,
      input_tokens: response.input_tokens,
      output_tokens: response.output_tokens
    )
  end

  private

  def build_messages(prompt, context)
    [
      { role: "system", content: context },
      { role: "user", content: prompt }
    ]
  end
end

# Production: real Anthropic client
client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])
service = Ai::CompletionService.new(client: client)

# Tests: fake client — no HTTP, no API key needed
fake_client = FakeCompletionClient.new(response: "Here is your refactored code...")
service = Ai::CompletionService.new(client: fake_client)

# Future: OpenAI, Ollama, or any LLM that implements .complete
ollama_client = Ollama::Client.new(base_url: "http://localhost:11434")
service = Ai::CompletionService.new(client: ollama_client)
```

Configuring dependencies at the application level:

```ruby
# config/initializers/dependencies.rb
Rails.application.config.after_initialize do
  # Wire up production dependencies
  embedding_client = Embeddings::HttpClient.new(
    base_url: ENV.fetch("EMBEDDING_SERVICE_URL")
  )

  Rails.application.config.x.embedding_client = embedding_client
  Rails.application.config.x.ai_client = Anthropic::Client.new(
    api_key: ENV.fetch("ANTHROPIC_API_KEY")
  )
end

# Services pull from config or accept injection
class Embeddings::IndexService
  def initialize(client: Rails.application.config.x.embedding_client)
    @client = client
  end

  def call(project, files)
    files.each do |path, content|
      vectors = @client.embed([content])
      project.code_embeddings.create!(file_path: path, embedding: vectors.first)
    end
  end
end
```

DIP with Ruby blocks — the lightest-weight dependency injection:

```ruby
class Orders::ExportService
  # The formatter is an injected dependency via block
  def call(orders, &formatter)
    formatter ||= method(:default_format)
    orders.map { |order| formatter.call(order) }
  end

  private

  def default_format(order)
    "#{order.reference}: $#{order.total}"
  end
end

# Different formats without modifying ExportService
Orders::ExportService.new.call(orders) { |o| o.to_json }
Orders::ExportService.new.call(orders) { |o| [o.reference, o.total].join(",") }
Orders::ExportService.new.call(orders)  # Uses default
```

## Why This Is Good

- **Swappable dependencies.** Production uses Anthropic, tests use a fake, future uses Ollama — `CompletionService` never changes. The high-level business logic is isolated from low-level API details.
- **Testable without infrastructure.** Tests inject fakes or doubles. No HTTP calls, no API keys, no external services. Tests run in milliseconds.
- **Framework-independent business logic.** `CompletionService` doesn't know about Rails, HTTP, or JSON parsing. It knows about messages and responses. The concrete client handles the transport.
- **Default injection balances convenience and flexibility.** `client: Rails.application.config.x.embedding_client` provides a sensible default while allowing test overrides. Production code doesn't need to specify the client every time.

## Anti-Pattern

Hardcoded dependencies — high-level logic directly instantiates low-level classes:

```ruby
class Ai::CompletionService
  def call(prompt, context:)
    # HARDCODED: directly creates the concrete client
    client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])

    messages = build_messages(prompt, context)
    response = client.messages.create(
      model: "claude-haiku-4-5-20251001",
      max_tokens: 4096,
      messages: messages
    )

    Result.new(
      content: response.content.first.text,
      input_tokens: response.usage.input_tokens,
      output_tokens: response.usage.output_tokens
    )
  end
end
```

```ruby
# Another violation: service directly calls a specific external API
class Embeddings::IndexService
  def call(project, files)
    files.each do |path, content|
      # HARDCODED: knows the exact URL, HTTP method, headers, and response format
      response = Faraday.post(
        "http://embedding-service:8000/embed",
        { texts: [content] }.to_json,
        "Content-Type" => "application/json"
      )
      vector = JSON.parse(response.body)["embeddings"].first
      project.code_embeddings.create!(file_path: path, embedding: vector)
    end
  end
end
```

## Why This Is Bad

- **Can't swap the provider.** Moving from Anthropic to OpenAI requires rewriting `CompletionService`. The business logic (building messages, processing responses) is tangled with the transport (HTTP client, API format).
- **Can't test without the real service.** Testing `CompletionService` requires either a running Anthropic API (slow, expensive, flaky) or complex WebMock stubs that mirror the exact API format. A fake client is simpler.
- **URL, headers, and JSON parsing inside business logic.** `IndexService` knows about Faraday, URLs, JSON parsing, and response structure. These are transport concerns that belong in a client class, not in the indexing logic.
- **Environment coupling.** `ENV["ANTHROPIC_API_KEY"]` is read every time the service is called. In tests, you must set the environment variable or the service breaks. With injection, tests pass a fake and never touch ENV.

## When To Apply

- **External services.** API clients, email services, payment gateways, embedding services — always inject these. They're the most common source of hard-to-test, hard-to-swap dependencies.
- **Cross-cutting concerns.** Logging, caching, metrics — inject them so you can swap implementations (stdout logger vs CloudWatch vs null logger for tests).
- **Strategy selection.** When behavior varies at runtime (different AI models, different export formats, different notification channels), inject the strategy.
- **Configuration that varies by environment.** Database connections, API URLs, feature flags — inject via Rails config or environment, not hardcoded values.

## When NOT To Apply

- **Don't inject Ruby standard library classes.** `Array.new`, `Hash.new`, `Time.current` — these are stable, universal dependencies. Injecting them adds ceremony with no benefit.
- **Don't inject ActiveRecord models.** `User.find(id)` is fine. You don't need to inject a "UserRepository" in Rails — that's Java-style over-abstraction.
- **Don't inject everything.** Inject *boundaries* — the edges where your code meets external systems. Internal collaborators (one service calling another within your app) can be directly referenced if they're stable.

## Edge Cases

**Circular dependencies:**
If ServiceA depends on ServiceB and ServiceB depends on ServiceA, you have a design problem. Extract the shared logic into a third class that both depend on.

**Default values vs mandatory injection:**
Use default values for production dependencies, mandatory injection for things that should always be explicit:

```ruby
# Default for convenience — production always uses the real client
def initialize(client: Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"]))

# Mandatory — caller must choose a strategy
def initialize(processor:)
  raise ArgumentError, "processor is required" unless processor
end
```

**Rails' built-in DIP mechanisms:**
Rails already uses DIP in many places: `config.active_job.queue_adapter`, `config.cache_store`, `config.active_storage.service`. These are configuration-based dependency injection. Follow the same pattern for your own services.
