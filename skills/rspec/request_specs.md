# RSpec: Request Specs

## Pattern

Test controllers through request specs, not controller specs. Request specs exercise the full middleware stack — routing, params parsing, authentication, the action, and the response — giving you confidence the endpoint works end to end.

```ruby
# spec/requests/orders_spec.rb
RSpec.describe "Orders", type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "GET /orders" do
    it "returns the user's orders" do
      create_list(:order, 3, user: user)
      create(:order) # belongs to another user

      get orders_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("3 orders")
    end
  end

  describe "POST /orders" do
    let(:product) { create(:product, stock: 10) }
    let(:valid_params) do
      {
        order: {
          shipping_address: "123 Main St",
          line_items_attributes: [{ product_id: product.id, quantity: 2 }]
        }
      }
    end

    context "with valid params" do
      it "creates an order" do
        expect {
          post orders_path, params: valid_params
        }.to change(Order, :count).by(1)
      end

      it "redirects to the order" do
        post orders_path, params: valid_params
        expect(response).to redirect_to(Order.last)
      end
    end

    context "with invalid params" do
      it "returns unprocessable entity" do
        post orders_path, params: { order: { shipping_address: "" } }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "does not create an order" do
        expect {
          post orders_path, params: { order: { shipping_address: "" } }
        }.not_to change(Order, :count)
      end
    end
  end

  describe "GET /orders/:id" do
    it "returns the order" do
      order = create(:order, user: user)
      get order_path(order)
      expect(response).to have_http_status(:ok)
    end

    it "returns not found for another user's order" do
      other_order = create(:order)
      expect {
        get order_path(other_order)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "DELETE /orders/:id" do
    it "destroys the order" do
      order = create(:order, user: user)
      expect {
        delete order_path(order)
      }.to change(Order, :count).by(-1)
    end

    it "redirects to the index" do
      order = create(:order, user: user)
      delete order_path(order)
      expect(response).to redirect_to(orders_path)
    end
  end
end
```

For JSON APIs:

```ruby
RSpec.describe "API::V1::Orders", type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{user.api_token}" } }

  describe "GET /api/v1/orders" do
    it "returns orders as JSON" do
      create_list(:order, 2, user: user)

      get "/api/v1/orders", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["orders"].length).to eq(2)
    end
  end

  describe "POST /api/v1/orders" do
    it "creates and returns the order" do
      post "/api/v1/orders", params: valid_params.to_json,
                             headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json["order"]["id"]).to be_present
    end
  end
end
```

## Why This Is Good

- **Tests what the user experiences.** A request spec hits the same code path as a real browser or API client. Routing, middleware, authentication, params parsing, the action, and the response are all exercised.
- **Catches integration bugs.** A controller spec might pass with the correct params, but a request spec catches a broken route, a missing authentication check, or a middleware that strips a header.
- **Rails official recommendation.** Since Rails 5, the Rails team recommends request specs over controller specs. Controller specs are considered legacy.
- **Simpler setup.** No `assigns` or `controller` objects to reason about. Just HTTP verbs, paths, params, and response assertions.

## Anti-Pattern

Using controller specs with `assigns` and internal assertions:

```ruby
# LEGACY — do not write new tests this way
RSpec.describe OrdersController, type: :controller do
  describe "GET #index" do
    it "assigns @orders" do
      order = create(:order)
      get :index
      expect(assigns(:orders)).to include(order)
    end

    it "renders the index template" do
      get :index
      expect(response).to render_template(:index)
    end
  end

  describe "POST #create" do
    it "assigns a new order" do
      post :create, params: { order: valid_attributes }
      expect(assigns(:order)).to be_a(Order)
      expect(assigns(:order)).to be_persisted
    end
  end
end
```

## Why This Is Bad

- **Tests implementation, not behavior.** `assigns(:orders)` tests that the controller set an instance variable — an implementation detail. The user doesn't care about instance variables; they care about what the page contains.
- **Skips the middleware stack.** Controller specs bypass routing, Rack middleware, and Devise authentication. A test can pass even if the route is broken or auth is misconfigured.
- **`assigns` is deprecated.** Rails removed `assigns` from the default stack. You need the `rails-controller-testing` gem to use it, which is a sign you're going against the grain.
- **Brittle.** If you rename an instance variable from `@orders` to `@user_orders`, every controller spec breaks even though the behavior is unchanged.

## When To Apply

- **Every controller endpoint gets a request spec.** This is not optional. If there's a route, there's a request spec.
- **Test the happy path and the primary failure path for each action.** Create → success + validation failure. Update → success + validation failure. Show → found + not found. Index → with data + empty.
- **Test authentication and authorization.** Unauthenticated access returns 401. Accessing another user's resource returns 404 (scoped query) or 403 (authorization check).

## When NOT To Apply

- **Don't test framework behavior.** Don't test that `before_action :authenticate_user!` calls Devise. Test that an unauthenticated request returns 401. The mechanism doesn't matter — the outcome does.
- **Don't test rendering details in request specs.** Use view specs or system specs for "the page shows the order total." Request specs check status codes, redirects, and JSON structure.
- **Don't test service object logic in request specs.** If `Orders::CreateService` has complex business logic, test it in a service spec. The request spec just verifies the controller delegates correctly and handles the result.

## Edge Cases

**Testing file uploads:**
Use `fixture_file_upload`:

```ruby
it "accepts an attachment" do
  file = fixture_file_upload("receipt.pdf", "application/pdf")
  post orders_path, params: { order: { receipt: file, **valid_params } }
  expect(response).to redirect_to(Order.last)
end
```

**Testing streaming responses:**
Request specs receive the full response after streaming completes. If you need to test the streaming behavior itself, use a system spec with Capybara.

**Shared authentication setup:**
Use a shared context to DRY up auth:

```ruby
RSpec.shared_context "authenticated user" do
  let(:user) { create(:user) }
  before { sign_in user }
end

RSpec.describe "Orders", type: :request do
  include_context "authenticated user"
end
```
