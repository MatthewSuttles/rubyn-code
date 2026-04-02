# Minitest: Mocking and Stubbing

## Pattern

Minitest includes `Minitest::Mock` for mocking and Ruby's `Object#stub` for stubbing. For more complex needs, use the `mocha` gem. Stub external dependencies, mock to verify interactions, and prefer dependency injection over global patching.

### Built-in Minitest::Mock

```ruby
class AiCompletionServiceTest < ActiveSupport::TestCase
  test "calls the client with correct params" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:complete, mock_response, [Array], model: String, max_tokens: Integer)

    service = Ai::CompletionService.new(client: mock_client)
    service.call("Refactor this code", context: "You are Rubyn.")

    mock_client.verify  # Raises if .complete wasn't called with expected args
  end

  test "returns content from response" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:complete, mock_response, [Array], model: String, max_tokens: Integer)

    service = Ai::CompletionService.new(client: mock_client)
    result = service.call("Refactor this code", context: "You are Rubyn.")

    assert_equal "Here is your refactored code", result.content
  end

  private

  def mock_response
    OpenStruct.new(
      content: "Here is your refactored code",
      input_tokens: 500,
      output_tokens: 200
    )
  end
end
```

### Object#stub (built into Minitest)

```ruby
class OrderTest < ActiveSupport::TestCase
  test "sends confirmation after creation" do
    # Stub the mailer to verify it's called
    OrderMailer.stub(:confirmation, mock_mail) do
      Orders::CreateService.call(valid_params, users(:alice))
    end
  end

  test "external API failure doesn't crash order creation" do
    WarehouseApi.stub(:notify, ->(*) { raise Faraday::TimeoutError }) do
      # The service should handle the error gracefully
      result = Orders::CreateService.call(valid_params, users(:alice))
      assert result.success?
    end
  end

  private

  def mock_mail
    mock = Minitest::Mock.new
    mock.expect(:deliver_later, true)
    mock
  end
end
```

### Mocha Gem (for more expressive mocking)

```ruby
# Gemfile
group :test do
  gem "mocha"
end

# test/test_helper.rb
require "mocha/minitest"
```

```ruby
class OrdersCreateServiceTest < ActiveSupport::TestCase
  test "sends confirmation email" do
    OrderMailer.expects(:confirmation).with(instance_of(Order)).returns(stub(deliver_later: true))

    Orders::CreateService.call(valid_params, users(:alice))
  end

  test "deducts credits from user" do
    user = users(:alice)
    user.expects(:deduct_credits!).with(1).once

    Credits::DeductionService.call(user: user, credits: 1)
  end

  test "does not send email when save fails" do
    OrderMailer.expects(:confirmation).never

    Orders::CreateService.call(invalid_params, users(:alice))
  end

  test "retries on timeout" do
    client = stub("ai_client")
    client.stubs(:complete)
          .raises(Faraday::TimeoutError).then
          .raises(Faraday::TimeoutError).then
          .returns(mock_response)

    service = Ai::CompletionService.new(client: client)
    result = service.call("test prompt", context: "test")

    assert_equal "response content", result.content
  end
end
```

### WebMock for HTTP Stubbing

```ruby
# test/test_helper.rb
require "webmock/minitest"

class ActiveSupport::TestCase
  # Disable real HTTP connections in tests
  WebMock.disable_net_connect!(allow_localhost: true)
end
```

```ruby
class EmbeddingClientTest < ActiveSupport::TestCase
  setup do
    stub_request(:post, "http://localhost:8000/embed")
      .with(body: hash_including("texts"))
      .to_return(
        status: 200,
        body: { embeddings: [[0.1, 0.2, 0.3]], dimensions: 1024, count: 1 }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  test "returns embeddings from the service" do
    client = Embeddings::HttpClient.new(base_url: "http://localhost:8000")
    result = client.embed(["def hello; end"])

    assert_equal 3, result.first.length
    assert_kind_of Float, result.first.first
  end

  test "raises on server error" do
    stub_request(:post, "http://localhost:8000/embed")
      .to_return(status: 500, body: "Internal Server Error")

    client = Embeddings::HttpClient.new(base_url: "http://localhost:8000")

    assert_raises Embeddings::ServerError do
      client.embed(["test"])
    end
  end
end
```

## Why This Is Good

- **`Minitest::Mock#verify` catches missing calls.** If the mock expected `.complete` to be called and it wasn't, the test fails. No silent passes.
- **`Object#stub` is temporary.** The stub only applies within the block. After the block, the original method is restored. No test pollution.
- **WebMock prevents real HTTP.** Accidental HTTP calls in tests fail immediately instead of silently hitting real APIs.
- **Mocha's `.expects` is expressive.** `.expects(:method).with(args).returns(value).once` reads clearly and verifies the interaction.

## Anti-Pattern

Over-mocking or mocking the object under test:

```ruby
# BAD: Mocking the thing you're testing
test "calculates total" do
  order = orders(:pending_order)
  order.stubs(:line_items).returns([
    stub(quantity: 2, unit_price: 10_00),
    stub(quantity: 1, unit_price: 25_00)
  ])

  assert_equal 45_00, order.total
  # You're testing that .sum works on stubs, not that order.total works
end
```

## Minitest Mock vs Mocha Comparison

| Feature | Minitest::Mock | Mocha |
|---|---|---|
| Setup | Built-in | `gem "mocha"` |
| Expect call | `mock.expect(:method, return, [args])` | `obj.expects(:method).with(args).returns(val)` |
| Stub | `object.stub(:method, return) { block }` | `obj.stubs(:method).returns(val)` |
| Verify | `mock.verify` (manual) | Automatic at test end |
| Sequence | Not built in | `sequence = sequence("name")` |
| Any instance | Not built in | `Order.any_instance.stubs(:save)` |
| Expressiveness | Minimal | Rich (`.once`, `.never`, `.at_least_once`) |

Use built-in mocks for simple cases. Use Mocha when you need `.expects`, `.never`, sequences, or `any_instance`.
