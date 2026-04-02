# Rails: Controller Concerns

## Pattern

Use controller concerns for cross-cutting HTTP behavior shared across multiple controllers — authentication helpers, pagination, error handling, and response formatting. Keep concerns focused on one capability.

```ruby
# app/controllers/concerns/authenticatable.rb
module Authenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
    helper_method :current_user
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end

  def authenticate_user!
    redirect_to login_path, alert: "Please log in" unless current_user
  end
end
```

```ruby
# app/controllers/concerns/paginatable.rb
module Paginatable
  extend ActiveSupport::Concern

  private

  def paginate(scope, per_page: 25)
    scope.page(params[:page]).per(per_page)
  end

  def pagination_meta(collection)
    {
      current_page: collection.current_page,
      total_pages: collection.total_pages,
      total_count: collection.total_count,
      per_page: collection.limit_value
    }
  end
end
```

```ruby
# app/controllers/concerns/api_error_handling.rb
module ApiErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound, with: :not_found
    rescue_from ActiveRecord::RecordInvalid, with: :unprocessable
    rescue_from ActionController::ParameterMissing, with: :bad_request
  end

  private

  def not_found(exception)
    render json: { error: "Not found", detail: exception.message }, status: :not_found
  end

  def unprocessable(exception)
    render json: { error: "Validation failed", details: exception.record.errors.full_messages }, status: :unprocessable_entity
  end

  def bad_request(exception)
    render json: { error: "Bad request", detail: exception.message }, status: :bad_request
  end
end
```

Usage — compose focused concerns:

```ruby
class Api::V1::BaseController < ActionController::API
  include Authenticatable
  include Paginatable
  include ApiErrorHandling
end

class Api::V1::OrdersController < Api::V1::BaseController
  def index
    orders = paginate(current_user.orders.recent)
    render json: { orders: orders, meta: pagination_meta(orders) }
  end
end
```

## Why This Is Good

- **Single responsibility per concern.** `Authenticatable` handles auth. `Paginatable` handles pagination. `ApiErrorHandling` handles errors. Each is independently understandable and testable.
- **Composable.** A controller includes the concerns it needs. An API controller includes `ApiErrorHandling`. A web controller includes `WebErrorHandling` instead. No monolithic base class.
- **DRY across controllers.** Pagination logic is identical across every index action. Writing it once in a concern prevents copy-paste and ensures consistency.
- **`rescue_from` in a concern centralizes error handling.** Every API controller inheriting from `BaseController` gets consistent error responses for common exceptions without any per-controller code.

## Anti-Pattern

Concerns with business logic, controller-specific behavior, or too many responsibilities:

```ruby
# BAD: Business logic in a controller concern
module OrderProcessing
  extend ActiveSupport::Concern

  private

  def process_order(order)
    validate_inventory(order)
    calculate_total(order)
    apply_discount(order)
    charge_payment(order)
    send_confirmation(order)
    notify_warehouse(order)
  end

  def validate_inventory(order)
    order.line_items.each do |item|
      raise "Out of stock" if item.product.stock < item.quantity
    end
  end

  def calculate_total(order)
    order.total = order.line_items.sum { |li| li.quantity * li.price }
  end

  # ... 50 more lines of business logic
end
```

```ruby
# BAD: Concern used by only one controller
module OrdersControllerHelpers
  extend ActiveSupport::Concern

  private

  def set_order
    @order = current_user.orders.find(params[:id])
  end

  def order_params
    params.require(:order).permit(:address, :notes)
  end
end
```

## Why This Is Bad

- **Business logic in a controller concern is still business logic in a controller.** Moving `process_order` from the controller to a concern doesn't fix the architecture — it just moves the problem to a different file. This belongs in a service object.
- **Single-use concerns add indirection.** `OrdersControllerHelpers` is included in one controller. Opening the controller, you see `include OrdersControllerHelpers` and have to navigate to another file to find `set_order`. Just define `set_order` in the controller directly.
- **Fat concerns replace fat controllers.** If the concern is 100 lines of business logic, the controller's responsibilities haven't shrunk — they've been scattered.

## When To Apply

- **Cross-cutting HTTP concerns** used by 3+ controllers: authentication, authorization, pagination, error handling, logging, CORS, request throttling.
- **Response formatting** shared across API controllers: consistent JSON error shapes, pagination metadata, HATEOAS links.
- **`before_action` chains** that are identical across controllers: `authenticate_user!`, `set_locale`, `verify_csrf_token`.

## When NOT To Apply

- **Business logic.** Inventory validation, payment processing, email sending — these belong in service objects, not controller concerns.
- **Behavior for one controller.** If only `OrdersController` uses it, keep it in `OrdersController`. A concern for one consumer is just indirection.
- **Model-level logic.** If the concern accesses `ActiveRecord` methods or database queries, it probably belongs on the model or in a query object, not in a controller concern.

## Edge Cases

**Concern needs configuration per controller:**
Use class methods or class attributes:

```ruby
module RateLimitable
  extend ActiveSupport::Concern

  included do
    class_attribute :rate_limit_per_minute, default: 60
    before_action :check_rate_limit
  end

  private

  def check_rate_limit
    key = "rate_limit:#{current_user.id}:#{controller_name}"
    count = Rails.cache.increment(key, 1, expires_in: 1.minute)
    head :too_many_requests if count > self.class.rate_limit_per_minute
  end
end

class Api::V1::AiController < Api::V1::BaseController
  include RateLimitable
  self.rate_limit_per_minute = 20  # Stricter limit for AI endpoints
end
```

**Testing concerns in isolation:**
Create an anonymous controller in the spec:

```ruby
RSpec.describe Authenticatable, type: :controller do
  controller(ApplicationController) do
    include Authenticatable

    def index
      render json: { user: current_user.email }
    end
  end

  it "redirects unauthenticated users" do
    get :index
    expect(response).to redirect_to(login_path)
  end
end
```
