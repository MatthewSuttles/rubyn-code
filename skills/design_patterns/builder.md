# Design Pattern: Builder

## Pattern

Construct complex objects step by step. The Builder pattern lets you produce different representations of an object using the same construction process. In Ruby, builders are often implemented as chainable method calls or configuration blocks.

```ruby
# Builder with chainable methods — idiomatic Ruby
class PromptBuilder
  def initialize
    @system_parts = []
    @messages = []
    @model = "claude-haiku-4-5-20251001"
    @max_tokens = 4096
    @temperature = 0.0
  end

  def system(content)
    @system_parts << content
    self
  end

  def best_practice(document)
    @system_parts << "## Best Practice: #{document.title}\n\n#{document.content}"
    self
  end

  def codebase_context(embeddings)
    context = embeddings.map { |e| "# #{e.file_path}\n```ruby\n#{e.chunk_content}\n```" }.join("\n\n")
    @system_parts << "## Relevant Codebase Context\n\n#{context}"
    self
  end

  def user(content)
    @messages << { role: "user", content: content }
    self
  end

  def assistant(content)
    @messages << { role: "assistant", content: content }
    self
  end

  def model(name)
    @model = name
    self
  end

  def max_tokens(n)
    @max_tokens = n
    self
  end

  def temperature(t)
    @temperature = t
    self
  end

  def build
    {
      model: @model,
      max_tokens: @max_tokens,
      temperature: @temperature,
      system: @system_parts.join("\n\n---\n\n"),
      messages: @messages
    }
  end
end

# Usage — reads like a recipe
prompt = PromptBuilder.new
  .system("You are Rubyn, an expert Ruby and Rails coding assistant.")
  .best_practice(service_objects_doc)
  .best_practice(callbacks_doc)
  .codebase_context(relevant_embeddings)
  .user("Refactor this controller action into a service object:\n\n```ruby\n#{code}\n```")
  .model("claude-haiku-4-5-20251001")
  .max_tokens(4096)
  .build
```

Builder with block configuration — Ruby convention:

```ruby
class QueryBuilder
  attr_reader :scope

  def initialize(base_scope)
    @scope = base_scope
  end

  def self.build(base_scope, &block)
    builder = new(base_scope)
    builder.instance_eval(&block) if block
    builder.scope
  end

  def where(**conditions)
    @scope = @scope.where(conditions)
  end

  def search(query)
    return unless query.present?
    @scope = @scope.where("name ILIKE ?", "%#{query}%")
  end

  def status(value)
    return unless value.present?
    @scope = @scope.where(status: value)
  end

  def date_range(from:, to:)
    @scope = @scope.where(created_at: from..to) if from && to
  end

  def sort_by(column, direction = :asc)
    @scope = @scope.order(column => direction)
  end

  def paginate(page:, per: 25)
    @scope = @scope.page(page).per(per)
  end
end

# Usage with block
orders = QueryBuilder.build(current_user.orders) do
  status params[:status]
  search params[:q]
  date_range from: params[:from], to: params[:to]
  sort_by :created_at, :desc
  paginate page: params[:page]
end
```

## Why This Is Good

- **Step-by-step construction.** Complex objects are built incrementally. Each step is named and self-documenting. The final `build` call assembles everything.
- **Optional steps.** Not every prompt needs best practices or codebase context. The builder doesn't care which steps are called or in what order.
- **Chainable API is readable.** `.system(...).best_practice(...).user(...)` reads as a sequence of construction steps. It's clearer than a constructor with 8 keyword arguments.
- **Separates construction from representation.** The same builder process can produce different outputs — a hash for the API, a string for logging, an object for testing.
- **Block form is idiomatic Ruby.** `QueryBuilder.build(scope) { status "active" }` follows Ruby conventions (like `Faraday.new { |f| f.adapter :net_http }`).

## When To Apply

- **Objects with many optional parts.** An API request with optional system prompt, codebase context, conversation history, model selection, and temperature.
- **Objects constructed in different configurations.** A query that sometimes has filters, sometimes has sorting, sometimes has pagination — but never all of them.
- **When a constructor has 5+ parameters.** The builder replaces a long argument list with named, chainable steps.
- **Testing.** Builders make it easy to create test fixtures with specific configurations without specifying every field.

## When NOT To Apply

- **Simple objects with 2-3 required fields.** `Order.new(user: user, total: 100)` doesn't need a builder.
- **Objects that are always constructed the same way.** If every construction uses the same steps, a factory method is simpler.
- **Don't create a builder just for one call site.** Builders shine when used from multiple places with different configurations.

## Rails Examples

Rails uses the builder pattern extensively — `Arel` query building, `ActionMailer` message construction, `ActiveStorage` attachment configuration. Follow the same pattern for your domain objects.
