# Sinatra: Testing with Rack::Test

## Pattern

Test Sinatra apps using `rack-test`, which provides HTTP method helpers that hit your app directly (no real HTTP server needed). Tests are fast, isolated, and exercise the full Rack middleware stack.

```ruby
# Gemfile
group :test do
  gem "rack-test"
  gem "minitest"
  gem "database_cleaner-active_record"
end
```

```ruby
# test/test_helper.rb
ENV["RACK_ENV"] = "test"

require_relative "../config/environment"
require "minitest/autorun"
require "minitest/pride"
require "rack/test"

class Minitest::Test
  include Rack::Test::Methods

  def app
    MyApp::Api
  end

  def json_body
    JSON.parse(last_response.body, symbolize_names: true)
  end

  def auth_header(user)
    { "HTTP_AUTHORIZATION" => "Bearer #{user.api_token}" }
  end

  def post_json(path, body, headers = {})
    post path, body.to_json, headers.merge("CONTENT_TYPE" => "application/json")
  end
end
```

```ruby
# test/routes/health_test.rb
require "test_helper"

class HealthTest < Minitest::Test
  def test_returns_ok
    get "/health"

    assert_equal 200, last_response.status
    assert_equal "ok", json_body[:status]
  end
end
```

```ruby
# test/routes/orders_test.rb
require "test_helper"

class OrdersTest < Minitest::Test
  def setup
    @user = User.create!(email: "alice@example.com", name: "Alice", api_token: "test-token-123")
    @order = Order.create!(user: @user, reference: "ORD-001", shipping_address: "123 Main", status: "pending", total: 50_00)
  end

  def teardown
    DatabaseCleaner.clean
  end

  # INDEX
  def test_index_returns_orders
    get "/orders", {}, auth_header(@user)

    assert_equal 200, last_response.status
    assert_equal 1, json_body[:orders].length
    assert_equal "ORD-001", json_body[:orders].first[:reference]
  end

  def test_index_requires_auth
    get "/orders"

    assert_equal 401, last_response.status
    assert_equal "Unauthorized", json_body[:error]
  end

  def test_index_only_returns_current_users_orders
    other_user = User.create!(email: "bob@example.com", name: "Bob", api_token: "bob-token")
    Order.create!(user: other_user, reference: "ORD-002", shipping_address: "456 Oak", status: "pending", total: 25_00)

    get "/orders", {}, auth_header(@user)

    references = json_body[:orders].map { |o| o[:reference] }
    assert_includes references, "ORD-001"
    refute_includes references, "ORD-002"
  end

  # SHOW
  def test_show_returns_order
    get "/orders/#{@order.id}", {}, auth_header(@user)

    assert_equal 200, last_response.status
    assert_equal "ORD-001", json_body[:order][:reference]
  end

  def test_show_returns_404_for_missing_order
    get "/orders/999999", {}, auth_header(@user)

    assert_equal 404, last_response.status
  end

  # CREATE
  def test_create_with_valid_params
    post_json "/orders", {
      shipping_address: "789 Elm St",
      line_items: [{ product_id: 1, quantity: 2 }]
    }, auth_header(@user)

    assert_equal 201, last_response.status
    assert json_body[:order][:id].present?
    assert_equal "pending", json_body[:order][:status]
  end

  def test_create_with_invalid_params
    post_json "/orders", { shipping_address: "" }, auth_header(@user)

    assert_equal 422, last_response.status
    assert json_body[:details].any?
  end

  def test_create_requires_auth
    post_json "/orders", { shipping_address: "123 Main" }

    assert_equal 401, last_response.status
  end

  # DELETE
  def test_delete_removes_order
    count_before = Order.count

    delete "/orders/#{@order.id}", {}, auth_header(@user)

    assert_equal 200, last_response.status
    assert_equal count_before - 1, Order.count
  end

  def test_delete_cannot_remove_other_users_order
    other_user = User.create!(email: "bob@example.com", name: "Bob", api_token: "bob-token")
    bobs_order = Order.create!(user: other_user, reference: "ORD-BOB", shipping_address: "456", status: "pending", total: 10_00)

    delete "/orders/#{bobs_order.id}", {}, auth_header(@user)

    assert_equal 404, last_response.status
    assert Order.exists?(bobs_order.id)  # Still exists
  end
end
```

Testing services (framework-independent):

```ruby
# test/services/orders/create_service_test.rb
require "test_helper"

class Orders::CreateServiceTest < Minitest::Test
  def setup
    @user = User.create!(email: "alice@example.com", name: "Alice", api_token: "token")
  end

  def test_creates_order_with_valid_params
    result = Orders::CreateService.call({ shipping_address: "123 Main" }, @user)

    assert result.success?
    assert_instance_of Order, result.order
    assert result.order.persisted?
  end

  def test_returns_failure_for_invalid_params
    result = Orders::CreateService.call({ shipping_address: "" }, @user)

    refute result.success?
    assert result.order.errors[:shipping_address].any?
  end

  def teardown
    DatabaseCleaner.clean
  end
end
```

## Why This Is Good

- **No HTTP server needed.** `rack-test` calls the app directly through Rack. Tests run in milliseconds, not seconds.
- **Full middleware stack.** Authentication middleware, JSON parsing, error handling — all exercised just like production.
- **`last_response` gives you everything.** Status code, body, headers, content type. Assert on any of them.
- **Service tests are framework-agnostic.** `Orders::CreateService.call(params, user)` is tested identically whether it's used in Sinatra, Rails, or a CLI tool.

## Key Methods

| Method | Purpose |
|---|---|
| `get "/path"` | GET request |
| `post "/path", body, headers` | POST request |
| `put "/path", body, headers` | PUT request |
| `delete "/path"` | DELETE request |
| `last_response.status` | HTTP status code |
| `last_response.body` | Response body string |
| `last_response.headers` | Response headers hash |
| `last_response.ok?` | Status is 200? |
| `last_response.redirect?` | Status is 3xx? |
| `follow_redirect!` | Follow a redirect |

## Anti-Pattern

Testing by starting a real HTTP server:

```ruby
# BAD: Starting a server for tests
def setup
  @server = Thread.new { MyApp::Api.run! port: 4567 }
  sleep 1  # Wait for server to start
end

def test_health
  response = Net::HTTP.get(URI("http://localhost:4567/health"))
  # Slow, flaky, port conflicts
end
```

Use `rack-test` — it's faster, more reliable, and doesn't need network ports.
