# RSpec: Testing Service Objects

## Pattern

Test service objects in isolation. Pass in dependencies as doubles. Assert on the result object, not on implementation details. Test the happy path, each failure mode, and edge cases.

```ruby
# spec/services/orders/create_service_spec.rb
RSpec.describe Orders::CreateService do
  let(:user) { create(:user) }
  let(:valid_params) do
    {
      shipping_address: "123 Main St",
      line_items_attributes: [
        { product_id: product.id, quantity: 2 }
      ]
    }
  end
  let(:product) { create(:product, stock: 10, price: 25.00) }

  describe ".call" do
    context "with valid params and sufficient stock" do
      it "returns a successful result" do
        result = described_class.call(valid_params, user)
        expect(result).to be_success
      end

      it "creates an order" do
        expect { described_class.call(valid_params, user) }
          .to change(Order, :count).by(1)
      end

      it "creates the order for the correct user" do
        result = described_class.call(valid_params, user)
        expect(result.order.user).to eq(user)
      end

      it "sends a confirmation email" do
        expect { described_class.call(valid_params, user) }
          .to have_enqueued_job(ActionMailer::MailDeliveryJob)
      end
    end

    context "with insufficient stock" do
      let(:product) { create(:product, stock: 0, price: 25.00) }

      it "returns a failed result" do
        result = described_class.call(valid_params, user)
        expect(result).not_to be_success
      end

      it "includes an error message" do
        result = described_class.call(valid_params, user)
        expect(result.order.errors[:base]).to include("Insufficient inventory")
      end

      it "does not create an order" do
        expect { described_class.call(valid_params, user) }
          .not_to change(Order, :count)
      end

      it "does not send a confirmation email" do
        expect { described_class.call(valid_params, user) }
          .not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
      end
    end

    context "with invalid params" do
      let(:invalid_params) { { shipping_address: "" } }

      it "returns a failed result" do
        result = described_class.call(invalid_params, user)
        expect(result).not_to be_success
      end

      it "returns validation errors on the order" do
        result = described_class.call(invalid_params, user)
        expect(result.order.errors).to be_present
      end
    end
  end
end
```

Testing service objects that call external services — inject doubles:

```ruby
# spec/services/embeddings/codebase_indexer_spec.rb
RSpec.describe Embeddings::CodebaseIndexer do
  let(:project) { create(:project) }
  let(:embedding_client) { instance_double(Embeddings::EmbeddingClient) }
  let(:fake_embeddings) { [Array.new(1024) { rand(-1.0..1.0) }] }

  subject(:indexer) { described_class.new(embedding_client: embedding_client) }

  before do
    allow(embedding_client).to receive(:embed).and_return(fake_embeddings)
  end

  describe "#index_file" do
    let(:file_content) do
      <<~RUBY
        class Order < ApplicationRecord
          belongs_to :user
          has_many :line_items

          def total
            line_items.sum(&:subtotal)
          end
        end
      RUBY
    end

    it "chunks the file into classes and methods" do
      indexer.index_file(project, "app/models/order.rb", file_content)
      chunks = project.code_embeddings

      expect(chunks.pluck(:chunk_type)).to include("class", "method")
    end

    it "calls the embedding client with chunk content" do
      expect(embedding_client).to receive(:embed).with(array_including(/class Order/))
      indexer.index_file(project, "app/models/order.rb", file_content)
    end

    it "stores embeddings on the project" do
      expect { indexer.index_file(project, "app/models/order.rb", file_content) }
        .to change(project.code_embeddings, :count).by_at_least(1)
    end

    it "records the file hash for change detection" do
      indexer.index_file(project, "app/models/order.rb", file_content)
      embedding = project.code_embeddings.last

      expect(embedding.file_hash).to eq(Digest::SHA256.hexdigest(file_content))
    end
  end
end
```

## Why This Is Good

- **Tests behavior, not implementation.** The test asserts `result.success?` and `result.order.user == user` — observable outcomes. It doesn't assert which internal methods were called or in what order.
- **Each context tests one scenario.** Happy path, insufficient stock, invalid params — each is a separate context with its own setup and assertions. A failure tells you exactly which scenario broke.
- **Injected dependencies are doubled.** `EmbeddingClient` is an `instance_double` — the test doesn't need a running Python service. It verifies the indexer calls the client correctly and processes the result.
- **`described_class.call`** uses the same interface as production code. The test is a client of the service, exercising it the way real code would.
- **Side effects are tested explicitly.** "sends a confirmation email" and "does not send a confirmation email" are separate assertions. The happy path verifies the side effect happens; the failure path verifies it doesn't.

## Anti-Pattern

Testing internal method calls, mocking the service itself, and mixing unit and integration concerns:

```ruby
# BAD: Testing implementation sequence
RSpec.describe Orders::CreateService do
  it "calls methods in order" do
    service = described_class.new(params, user)
    expect(service).to receive(:validate_inventory).ordered
    expect(service).to receive(:create_order).ordered
    expect(service).to receive(:charge_payment).ordered
    expect(service).to receive(:send_confirmation).ordered
    service.call
  end
end

# BAD: Mocking the service you're testing
RSpec.describe Orders::CreateService do
  it "creates an order" do
    service = described_class.new(params, user)
    allow(service).to receive(:validate_inventory).and_return(true)
    allow(service).to receive(:send_confirmation)
    result = service.call
    expect(result).to be_success
  end
end

# BAD: Integration test disguised as a unit test
RSpec.describe Orders::CreateService do
  it "processes the order completely" do
    result = described_class.call(params, user)
    expect(result).to be_success
    expect(Order.count).to eq(1)
    expect(ActionMailer::Base.deliveries.count).to eq(1)
    expect(Product.first.stock).to eq(8)
    expect(user.reload.loyalty_points).to eq(10)
    expect(WarehouseApi).to have_received(:notify)
    expect(Analytics).to have_received(:track)
  end
end
```

## Why This Is Bad

- **Testing method order is fragile.** Reordering internal steps breaks the test even if the behavior is correct. The user doesn't care if validation happens before or after order creation — they care about the result.
- **Mocking the subject is circular.** If you stub `validate_inventory` to return true, you're not testing that validation works — you're testing that the service calls `create_order` after something returns true. The test proves nothing about real behavior.
- **God assertions test everything at once.** When this test fails, which part broke? The order? The email? The stock update? The loyalty points? You have to read the failure message carefully and run the test in isolation to figure it out. Split into focused examples.

## When To Apply

- **Every service object gets its own spec file.** If you wrote a service, you write a spec. No exceptions.
- **Test the `.call` interface.** Don't test private methods directly. Test them through the public interface. If a private method has complex logic worth testing independently, it might belong in its own class.
- **Inject and double external dependencies.** HTTP clients, mailers, external APIs, other services — anything that crosses a boundary gets doubled.
- **Test each outcome in its own context.** Success, each type of failure, and edge cases each get their own `context` block with focused assertions.

## When NOT To Apply

- **Don't unit test trivial services.** A service that wraps a single `Model.create!` call with no logic doesn't need its own spec. Test it through a request spec instead.
- **Don't test private methods.** If you feel the need, either the private method is complex enough to be its own class, or you can test it through the public interface.
- **Integration between services is tested in request specs.** The controller calls ServiceA which calls ServiceB — test this flow through a request spec, not by testing ServiceA's use of ServiceB.

## Edge Cases

**Service returns different result types:**
Test each result type explicitly:

```ruby
context "when payment fails" do
  it "returns result with :payment_failed error" do
    result = described_class.call(params, user)
    expect(result.error_code).to eq(:payment_failed)
    expect(result.error).to include("card was declined")
  end
end

context "when validation fails" do
  it "returns result with :invalid error" do
    result = described_class.call(invalid_params, user)
    expect(result.error_code).to eq(:invalid)
  end
end
```

**Service wraps a transaction:**
Test that the transaction rolls back on failure:

```ruby
context "when notification fails after order creation" do
  before do
    allow(notifier).to receive(:notify).and_raise(StandardError, "API down")
  end

  it "rolls back the order" do
    expect { described_class.call(params, user) }.to raise_error(StandardError)
    expect(Order.count).to eq(0)
  end
end
```

**Testing the Result/Response object:**
If your services return a Result struct, test it as a value object:

```ruby
it "returns a result with the order" do
  result = described_class.call(valid_params, user)

  aggregate_failures do
    expect(result).to be_success
    expect(result.order).to be_persisted
    expect(result.order.total).to eq(50.00)
  end
end
```
