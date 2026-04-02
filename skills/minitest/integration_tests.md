# Minitest: Integration Tests (Controllers)

## Pattern

Rails integration tests (`ActionDispatch::IntegrationTest`) test the full request/response cycle — routing, middleware, authentication, controller action, and response. They're the Minitest equivalent of RSpec request specs.

```ruby
# test/controllers/orders_controller_test.rb
class OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @order = orders(:pending_order)
    sign_in @user
  end

  # INDEX
  test "index returns success" do
    get orders_path

    assert_response :success
  end

  test "index shows only current user's orders" do
    get orders_path

    assert_match @order.reference, response.body
    assert_no_match orders(:bobs_order).reference, response.body
  end

  # SHOW
  test "show returns the order" do
    get order_path(@order)

    assert_response :success
    assert_match @order.reference, response.body
  end

  test "show returns not found for another user's order" do
    assert_raises ActiveRecord::RecordNotFound do
      get order_path(orders(:bobs_order))
    end
  end

  # CREATE
  test "create with valid params" do
    assert_difference "Order.count", 1 do
      post orders_path, params: {
        order: {
          shipping_address: "789 Elm St",
          line_items_attributes: [
            { product_id: products(:widget).id, quantity: 2 }
          ]
        }
      }
    end

    assert_redirected_to Order.last
    follow_redirect!
    assert_match "Order placed", response.body
  end

  test "create with invalid params renders new" do
    assert_no_difference "Order.count" do
      post orders_path, params: { order: { shipping_address: "" } }
    end

    assert_response :unprocessable_entity
  end

  test "create sends confirmation email" do
    assert_emails 1 do
      post orders_path, params: {
        order: { shipping_address: "789 Elm", line_items_attributes: [{ product_id: products(:widget).id, quantity: 1 }] }
      }
    end
  end

  # UPDATE
  test "update changes the order" do
    patch order_path(@order), params: { order: { shipping_address: "New Address" } }

    assert_redirected_to @order
    assert_equal "New Address", @order.reload.shipping_address
  end

  # DESTROY
  test "destroy removes the order" do
    assert_difference "Order.count", -1 do
      delete order_path(@order)
    end

    assert_redirected_to orders_path
  end

  # AUTH
  test "redirects unauthenticated users" do
    sign_out
    get orders_path

    assert_redirected_to login_path
  end

  private

  def sign_in(user)
    post login_path, params: { email: user.email, password: "password" }
  end

  def sign_out
    delete logout_path
  end
end
```

### JSON API Tests

```ruby
# test/controllers/api/v1/orders_controller_test.rb
class Api::V1::OrdersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:alice)
    @api_key = api_keys(:alice_key)
  end

  test "index returns JSON" do
    get api_v1_orders_path, headers: auth_headers

    assert_response :success
    json = JSON.parse(response.body)
    assert_kind_of Array, json["orders"]
    assert_equal @user.orders.count, json["orders"].length
  end

  test "create returns 201" do
    assert_difference "Order.count", 1 do
      post api_v1_orders_path,
           params: { order: { shipping_address: "123 Main" } }.to_json,
           headers: auth_headers.merge("Content-Type" => "application/json")
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert json["order"]["id"].present?
    assert_equal "pending", json["order"]["status"]
  end

  test "returns 401 without API key" do
    get api_v1_orders_path

    assert_response :unauthorized
  end

  test "returns 401 with revoked API key" do
    @api_key.update!(revoked_at: 1.hour.ago)

    get api_v1_orders_path, headers: auth_headers

    assert_response :unauthorized
  end

  private

  def auth_headers
    { "Authorization" => "Bearer #{@api_key.raw_key}" }
  end
end
```

## Why This Is Good

- **Full stack testing.** Routes, middleware, auth, params parsing, the action, and the response — all exercised in one test. If the route is broken or auth is misconfigured, the test catches it.
- **`assert_difference` is atomic.** Captures count before, runs the block, checks count after. Cleaner than manual before/after variables.
- **`assert_emails` and `assert_enqueued_jobs` verify side effects.** No need to mock mailers or job queues — assert that the right things were enqueued.
- **`follow_redirect!` tests the full flow.** Create → redirect → show page with flash message. One test verifies the entire user journey.

## Anti-Pattern

Testing controller internals instead of HTTP behavior:

```ruby
# BAD: Testing instance variables (don't exist in integration tests)
test "assigns orders" do
  get orders_path
  assert_equal Order.all, assigns(:orders)  # assigns doesn't work in integration tests
end

# BAD: Testing which template rendered (implementation detail)
test "renders index template" do
  get orders_path
  assert_template :index  # Deprecated in integration tests
end
```

## When To Apply

- **Every controller endpoint gets integration tests.** Happy path, validation failure, auth checks, and authorization for each action.
- **Test what the user experiences.** Status codes, redirects, response body content, flash messages — not internal state.
- **Prefer `assert_response` + `assert_match` over template assertions.** Test the output, not the mechanism.

## Key Differences from RSpec Request Specs

| Minitest | RSpec |
|---|---|
| `assert_response :success` | `expect(response).to have_http_status(:ok)` |
| `assert_difference "Order.count", 1 do` | `expect { ... }.to change(Order, :count).by(1)` |
| `assert_redirected_to path` | `expect(response).to redirect_to(path)` |
| `assert_emails 1 do` | `expect { ... }.to have_enqueued_mail.once` |
| `JSON.parse(response.body)` | `JSON.parse(response.body)` (same) |
| `setup do` | `before do` |
| `fixtures :all` | `let(:user) { create(:user) }` |
