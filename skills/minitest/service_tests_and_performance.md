# Minitest: Testing Service Objects

## Pattern

Test service objects by calling `.call` with real or fixture data. Assert on the result object, side effects (DB changes, jobs enqueued, emails sent), and error conditions. Inject doubles for external dependencies.

```ruby
# test/services/orders/create_service_test.rb
require "test_helper"

class Orders::CreateServiceTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @product = products(:widget)
  end

  test "creates an order with valid params" do
    result = Orders::CreateService.call(valid_params, @user)

    assert result.success?
    assert_instance_of Order, result.order
    assert_equal "pending", result.order.status
    assert_equal @user, result.order.user
  end

  test "creates a database record" do
    assert_difference "Order.count", 1 do
      Orders::CreateService.call(valid_params, @user)
    end
  end

  test "sends confirmation email" do
    assert_emails 1 do
      Orders::CreateService.call(valid_params, @user)
    end
  end

  test "enqueues warehouse notification" do
    assert_enqueued_with(job: WarehouseNotificationJob) do
      Orders::CreateService.call(valid_params, @user)
    end
  end

  test "returns failure for invalid params" do
    result = Orders::CreateService.call({ shipping_address: "" }, @user)

    refute result.success?
    assert result.order.errors[:shipping_address].any?
  end

  test "does not create record on failure" do
    assert_no_difference "Order.count" do
      Orders::CreateService.call({ shipping_address: "" }, @user)
    end
  end

  test "does not send email on failure" do
    assert_no_emails do
      Orders::CreateService.call({ shipping_address: "" }, @user)
    end
  end

  private

  def valid_params
    {
      shipping_address: "123 Main St",
      line_items_attributes: [
        { product_id: @product.id, quantity: 2 }
      ]
    }
  end
end
```

Testing services with external dependencies:

```ruby
# test/services/embeddings/codebase_indexer_test.rb
require "test_helper"

class Embeddings::CodebaseIndexerTest < ActiveSupport::TestCase
  setup do
    @project = projects(:rubyn_project)
    @fake_embedder = FakeEmbedder.new
    @indexer = Embeddings::CodebaseIndexer.new(embedding_client: @fake_embedder)
  end

  test "creates code embeddings for each chunk" do
    file_content = <<~RUBY
      class Order < ApplicationRecord
        def total
          line_items.sum(&:subtotal)
        end
      end
    RUBY

    assert_difference "@project.code_embeddings.count" do
      @indexer.index_file(@project, "app/models/order.rb", file_content)
    end
  end

  test "stores the file path on each embedding" do
    @indexer.index_file(@project, "app/models/order.rb", "class Order; end")

    embedding = @project.code_embeddings.last
    assert_equal "app/models/order.rb", embedding.file_path
  end

  test "stores a file hash for change detection" do
    content = "class Order; end"
    @indexer.index_file(@project, "app/models/order.rb", content)

    embedding = @project.code_embeddings.last
    assert_equal Digest::SHA256.hexdigest(content), embedding.file_hash
  end

  test "skips unchanged files" do
    content = "class Order; end"
    @indexer.index_file(@project, "app/models/order.rb", content)

    assert_no_difference "@project.code_embeddings.count" do
      @indexer.index_file(@project, "app/models/order.rb", content)
    end
  end
end

# test/support/fake_embedder.rb
class FakeEmbedder
  DIMENSIONS = 1024

  def embed(texts)
    texts.map { Array.new(DIMENSIONS) { rand(-1.0..1.0) } }
  end

  def embed_query(text)
    Array.new(DIMENSIONS) { rand(-1.0..1.0) }
  end
end
```

# Minitest: Test Performance

## Pattern

Keep the suite fast: use fixtures, parallelize, avoid unnecessary DB writes, and profile regularly.

```ruby
# test/test_helper.rb
class ActiveSupport::TestCase
  # Run tests in parallel across CPU cores
  parallelize(workers: :number_of_processors)

  # Use transactions (default) — fastest cleanup strategy
  # Each test rolls back, no data persists between tests
  self.use_transactional_tests = true

  fixtures :all
end
```

### Profile slow tests

```bash
# Find the 10 slowest tests
bundle exec rails test --verbose 2>&1 | sort -t= -k2 -rn | head -10

# Or use minitest-reporters for detailed timing
```

```ruby
# Gemfile
group :test do
  gem "minitest-reporters"
end

# test/test_helper.rb
require "minitest/reporters"
Minitest::Reporters.use! [
  Minitest::Reporters::DefaultReporter.new,
  Minitest::Reporters::MeanTimeReporter.new  # Tracks average test times
]
```

### Speed tips

```ruby
# FAST: Use fixtures (zero per-test cost)
test "something with alice" do
  assert users(:alice).valid?
end

# SLOW: Creating records per test
test "something with a user" do
  user = User.create!(email: "test@example.com", name: "Test", password: "password")
  assert user.valid?
end

# FAST: Test pure logic without DB
test "money arithmetic" do
  price = Money.new(10_00)
  tax = price * 0.08

  assert_equal Money.new(80), tax
end

# FAST: Build without saving when testing validations
test "requires email" do
  user = User.new(email: nil)
  refute user.valid?
end

# FAST: Stub slow external calls
test "handles API timeout" do
  WarehouseApi.stub(:notify, ->(*) { raise Faraday::TimeoutError }) do
    result = Orders::ShipService.call(orders(:pending_order))
    refute result.success?
  end
end
```

### Parallel test configuration

```ruby
# For system tests or tests that need separate DB state
class ActiveSupport::TestCase
  parallelize(workers: :number_of_processors)

  # If parallel tests have DB issues, use:
  parallelize_setup do |worker|
    ActiveStorage::Blob.service.root = "#{ActiveStorage::Blob.service.root}-#{worker}"
  end
end
```

## Speed Hierarchy

1. **Pure Ruby assertions** (no DB) — microseconds
2. **Fixture reads** — microseconds (data already loaded)
3. **`User.new` + `.valid?`** — milliseconds (no DB write)
4. **Single `create!`** — ~1-5ms
5. **Factory with associations** — ~5-50ms (cascading creates)
6. **Integration test** — ~10-100ms (full request cycle)
7. **System test with browser** — ~500ms-5s

Optimize by pushing tests as high on this list as possible. Don't use an integration test when a unit test will do. Don't create records when fixtures exist.
