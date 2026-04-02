# Design Pattern: Adapter

## Pattern

Convert the interface of one class into another interface that clients expect. Adapters let classes work together that couldn't otherwise because of incompatible interfaces. In Rails, adapters are essential at system boundaries — wrapping external APIs, gems, and services behind a consistent internal interface.

```ruby
# Your app's internal interface — what your code expects
# Contract: .embed(texts) → Array<Array<Float>>

# Adapter for the Rubyn embedding service (FastAPI sidecar)
class Embeddings::RubynAdapter
  def initialize(base_url:)
    @base_url = base_url
    @conn = Faraday.new(url: base_url) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def embed(texts)
    response = @conn.post("/embed", { texts: texts, prefix: "passage" })
    response.body["embeddings"]
  end
end

# Adapter for OpenAI's embedding API (different URL, auth, response format)
class Embeddings::OpenAiAdapter
  def initialize(api_key:)
    @conn = Faraday.new(url: "https://api.openai.com") do |f|
      f.request :json
      f.response :json
      f.headers["Authorization"] = "Bearer #{api_key}"
    end
  end

  def embed(texts)
    response = @conn.post("/v1/embeddings", {
      model: "text-embedding-3-small",
      input: texts
    })
    # OpenAI returns { data: [{ embedding: [...] }, ...] }
    # We normalize to Array<Array<Float>> to match our interface
    response.body["data"]
      .sort_by { |d| d["index"] }
      .map { |d| d["embedding"] }
  end
end

# Adapter for a local model via ONNX Runtime (completely different mechanism)
class Embeddings::LocalOnnxAdapter
  def initialize(model_path:)
    @session = OnnxRuntime::InferenceSession.new(model_path)
  end

  def embed(texts)
    inputs = texts.map { |text| tokenize(text) }
    outputs = @session.run(nil, { input_ids: inputs })
    outputs.first # Already Array<Array<Float>>
  end

  private

  def tokenize(text)
    # Tokenization logic
  end
end

# Your service code doesn't know or care which adapter it uses
class Codebase::IndexService
  def initialize(embedder:)
    @embedder = embedder  # Any adapter works
  end

  def call(project, files)
    files.each_slice(10) do |batch|
      contents = batch.map(&:last)
      vectors = @embedder.embed(contents)  # Same interface, any provider
      batch.zip(vectors).each do |(path, _), vector|
        project.code_embeddings.upsert(
          { file_path: path, embedding: vector },
          unique_by: [:project_id, :file_path]
        )
      end
    end
  end
end

# Wire up in config
embedder = Embeddings::RubynAdapter.new(base_url: ENV["EMBEDDING_SERVICE_URL"])
# OR: Embeddings::OpenAiAdapter.new(api_key: ENV["OPENAI_API_KEY"])
# OR: Embeddings::LocalOnnxAdapter.new(model_path: "models/code-embed.onnx")

Codebase::IndexService.new(embedder: embedder).call(project, files)
```

Adapting a gem's interface to your domain:

```ruby
# The Stripe gem returns Stripe::Charge objects with their own structure.
# Your app works with a consistent PaymentResult.

PaymentResult = Data.define(:success, :transaction_id, :amount_cents, :error)

class Payments::StripeAdapter
  def charge(amount_cents:, token:, description:)
    charge = Stripe::Charge.create(
      amount: amount_cents,
      currency: "usd",
      source: token,
      description: description
    )
    PaymentResult.new(
      success: true,
      transaction_id: charge.id,
      amount_cents: charge.amount,
      error: nil
    )
  rescue Stripe::CardError => e
    PaymentResult.new(success: false, transaction_id: nil, amount_cents: 0, error: e.message)
  rescue Stripe::StripeError => e
    PaymentResult.new(success: false, transaction_id: nil, amount_cents: 0, error: "Payment service error")
  end
end

class Payments::BraintreeAdapter
  def charge(amount_cents:, token:, description:)
    result = Braintree::Transaction.sale(
      amount: (amount_cents / 100.0).round(2),
      payment_method_nonce: token,
      options: { submit_for_settlement: true }
    )
    if result.success?
      PaymentResult.new(
        success: true,
        transaction_id: result.transaction.id,
        amount_cents: (result.transaction.amount * 100).to_i,
        error: nil
      )
    else
      PaymentResult.new(success: false, transaction_id: nil, amount_cents: 0, error: result.message)
    end
  end
end
```

## Why This Is Good

- **Unified interface across providers.** `embedder.embed(texts)` works identically whether the backend is your Python sidecar, OpenAI, or a local ONNX model. Business logic never sees provider-specific details.
- **Provider-specific complexity is contained.** OpenAI's response format (`{ data: [{ embedding, index }] }`) is normalized inside the adapter. Nobody else in the codebase deals with that structure.
- **Swappable at configuration time.** Switching from OpenAI to your own model means changing one line in an initializer. No business logic changes, no test changes.
- **Error normalization.** Each adapter catches its own exceptions (Stripe::CardError, Braintree errors) and returns a consistent `PaymentResult`. The caller never rescues provider-specific errors.
- **Gem upgrades are isolated.** If Stripe changes their API, only `StripeAdapter` changes. Every other class in your app is insulated.

## When To Apply

- **Every external API integration.** Wrap third-party APIs in adapters from day one. Even if you'll never switch providers, the adapter isolates your code from their API changes.
- **When migrating between providers.** Build the new adapter, test it, swap the configuration. Both adapters coexist during migration.
- **Normalizing inconsistent interfaces.** Two gems that do similar things with different method names and return types — adapt them to one internal interface.

## When NOT To Apply

- **Internal classes with consistent interfaces.** You don't need an adapter between your own service objects if they already share an interface.
- **Don't over-abstract stable gems.** If you use Devise and will always use Devise, wrapping every Devise method in an adapter is pointless friction.
- **Single-use, simple integrations.** A one-off API call in a rake task doesn't need a full adapter class.

## Edge Cases

**Adapter + Decorator composition:**
Adapters normalize the interface. Decorators add cross-cutting behavior. They compose naturally:

```ruby
embedder = Embeddings::RubynAdapter.new(base_url: url)   # Normalize interface
embedder = Embeddings::RetryDecorator.new(embedder)       # Add retry
embedder = Embeddings::LoggingDecorator.new(embedder)     # Add logging
# Result: logged, retried, normalized embedding calls
```

**Testing adapters:**
Test each adapter against a shared example that defines the contract:

```ruby
RSpec.shared_examples "an embedding adapter" do
  it "returns an array of float arrays" do
    result = subject.embed(["def hello; end"])
    expect(result).to be_an(Array)
    expect(result.first).to all(be_a(Float))
  end
end
```
