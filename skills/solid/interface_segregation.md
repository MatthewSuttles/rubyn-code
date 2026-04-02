# SOLID: Interface Segregation Principle (ISP)

## Pattern

No client should be forced to depend on methods it doesn't use. In Ruby — where interfaces are implicit (duck typing) — ISP means: keep your modules, mixins, and object contracts small and focused. Don't force an object to implement capabilities it doesn't need.

```ruby
# GOOD: Focused, small interfaces via separate modules

module Printable
  def to_pdf
    raise NotImplementedError
  end
end

module Exportable
  def to_csv
    raise NotImplementedError
  end

  def to_json(*)
    raise NotImplementedError
  end
end

module Notifiable
  def send_notification
    raise NotImplementedError
  end
end

# Order needs all three
class Order < ApplicationRecord
  include Printable
  include Exportable
  include Notifiable

  def to_pdf
    OrderPdfGenerator.new(self).generate
  end

  def to_csv
    [reference, user.email, total, status].join(",")
  end

  def to_json(*)
    { reference: reference, total: total, status: status }.to_json
  end

  def send_notification
    OrderMailer.confirmation(self).deliver_later
  end
end

# Receipt only needs printing — not forced to implement export or notifications
class Receipt < ApplicationRecord
  include Printable

  def to_pdf
    ReceiptPdfGenerator.new(self).generate
  end
end

# Report only needs export — not forced to implement printing or notifications
class MonthlyReport
  include Exportable

  def to_csv
    # ... generate CSV
  end

  def to_json(*)
    # ... generate JSON
  end
end
```

ISP applied to service dependencies:

```ruby
# GOOD: Service depends only on what it needs

# Instead of depending on the entire User model:
class WelcomeEmailService
  # Only needs an email address and a name — not 30 User methods
  def call(email:, name:)
    WelcomeMailer.send(email: email, name: name).deliver_later
  end
end

# Caller provides only what's needed
WelcomeEmailService.new.call(email: user.email, name: user.name)

# The service can also be called with non-User data:
WelcomeEmailService.new.call(email: "invite@example.com", name: "New Friend")
```

ISP with dependency injection — narrow interfaces:

```ruby
# GOOD: The indexer only needs objects that respond to #embed
# It doesn't care if the client also has #health, #version, #warm_up

class Codebase::Indexer
  def initialize(embedder:)
    @embedder = embedder  # Only needs: embedder.embed(texts) → Array<Array<Float>>
  end

  def index(project, files)
    files.each do |path, content|
      chunks = Chunker.split(content)
      vectors = @embedder.embed(chunks.map(&:text))  # The only method we call
      chunks.zip(vectors).each do |chunk, vector|
        project.code_embeddings.create!(
          file_path: path,
          chunk_content: chunk.text,
          embedding: vector
        )
      end
    end
  end
end

# Any of these work — they all respond to #embed
Codebase::Indexer.new(embedder: EmbeddingClient.new)        # Real client
Codebase::Indexer.new(embedder: FakeEmbedder.new)           # Test double
Codebase::Indexer.new(embedder: CachedEmbedder.new(client)) # Decorator
```

## Why This Is Good

- **Models include only what they need.** `Receipt` includes `Printable` but not `Exportable`. It's never forced to stub out `to_csv` or `to_json` with `raise NotImplementedError`.
- **Services depend on narrow interfaces.** `WelcomeEmailService` needs an email and a name — not a 30-method User object. It works with any data source that provides those two values.
- **Testing is simpler.** To test `Codebase::Indexer`, you provide an object that responds to `embed`. You don't need to mock the 5 other methods on `EmbeddingClient`.
- **Changes are isolated.** If `Exportable` adds a `to_xml` method, only classes that include `Exportable` are affected. `Receipt` (which only includes `Printable`) is untouched.

## Anti-Pattern

A fat module that forces every includer to implement everything:

```ruby
# BAD: One massive module forces all methods on every includer
module DocumentCapabilities
  def to_pdf
    raise NotImplementedError
  end

  def to_csv
    raise NotImplementedError
  end

  def to_json(*)
    raise NotImplementedError
  end

  def to_xml
    raise NotImplementedError
  end

  def send_email
    raise NotImplementedError
  end

  def send_sms
    raise NotImplementedError
  end

  def archive
    raise NotImplementedError
  end

  def encrypt
    raise NotImplementedError
  end
end

# Receipt only needs PDF but is forced to "implement" everything
class Receipt < ApplicationRecord
  include DocumentCapabilities

  def to_pdf
    ReceiptPdfGenerator.new(self).generate
  end

  # These all raise NotImplementedError — they shouldn't exist on Receipt at all
  # But the module forced them in
end
```

## Why This Is Bad

- **Receipt responds to 8 methods it can't do.** `receipt.respond_to?(:send_sms)` returns `true`, but calling it raises `NotImplementedError`. The interface lies about the object's capabilities.
- **Forced implementation of irrelevant methods.** A developer including `DocumentCapabilities` must consider all 8 methods. They waste time figuring out which ones their class needs and stub the rest.
- **Brittle to change.** Adding a new method to `DocumentCapabilities` (say, `to_parquet`) requires every includer to either implement it or get a `NotImplementedError`. One module change ripples across all including classes.
- **Violates LSP.** If code calls `.send_sms` on any object including `DocumentCapabilities`, some objects work and others raise. The contract is unreliable.

## When To Apply

- **When a module/mixin has more than 4-5 methods and not all includers need all of them.** Split it into focused sub-modules.
- **When a service or method accepts a complex object but only uses 1-2 attributes.** Accept those attributes directly instead of the whole object.
- **When you inject dependencies.** Define the narrowest interface the consumer needs. Document what methods are required. Don't pass the kitchen sink.
- **In gems and libraries.** Public interfaces should be minimal. Don't force gem users to configure 10 options when they only need 2.

## When NOT To Apply

- **Don't split a 3-method module into 3 single-method modules.** ISP is about avoiding *fat* interfaces, not achieving one-method-per-module granularity.
- **ActiveRecord models inherently have many methods.** That's the framework's design. Don't fight it by wrapping every model in a narrow interface object for internal use.
- **Small, cohesive modules are already ISP-compliant.** A `Sluggable` module with `generate_slug` and `to_param` is fine — both methods are part of the same concept.

## Edge Cases

**Ruby's duck typing IS interface segregation:**
When you write a method that calls `object.each`, you've defined a one-method interface. Any Enumerable works. Ruby's duck typing naturally encourages narrow interfaces — lean into it.

```ruby
# This method's "interface" is: responds to .each and yields items with .email
def collect_emails(collection)
  collection.each_with_object([]) { |item, emails| emails << item.email }
end

# Works with any collection of objects that have .email
collect_emails(User.active)
collect_emails([subscriber_a, subscriber_b])
collect_emails(team.members)
```

**Frozen value objects as narrow interfaces:**
Instead of passing a User model to a service, pass a data object with only the needed attributes:

```ruby
NotificationPayload = Data.define(:email, :name, :phone)

payload = NotificationPayload.new(email: user.email, name: user.name, phone: user.phone)
NotificationService.call(payload)
```

This makes the dependency explicit and narrow.
