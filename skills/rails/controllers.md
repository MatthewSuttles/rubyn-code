# Rails: Skinny Controllers

## Pattern

Controllers handle HTTP concerns only: receive params, delegate to a service or model, respond with the appropriate format and status code. Business logic, data transformation, and side effects live elsewhere.

A well-structured controller action follows this shape:

```ruby
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  before_action :set_order, only: [:show, :update, :destroy]

  def index
    @orders = Current.user.orders.recent.page(params[:page])
  end

  def show
  end

  def create
    result = Orders::CreateService.call(order_params, current_user)

    if result.success?
      redirect_to result.order, notice: "Order placed."
    else
      @order = result.order
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @order.update(order_params)
      redirect_to @order, notice: "Order updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @order.destroy
    redirect_to orders_path, notice: "Order deleted."
  end

  private

  def set_order
    @order = Current.user.orders.find(params[:id])
  end

  def order_params
    params.require(:order).permit(:shipping_address, :notes)
  end
end
```

Key principles:
- Each action is 1-5 lines of logic (excluding private methods)
- `before_action` for shared record loading
- Private methods only for param filtering and record lookup
- No business logic, no conditional branching beyond success/failure
- Delegate complex operations to service objects
- Use `Current` attributes or scoped queries — never `Order.find(params[:id])` without scoping to the user

When an action needs more than simple CRUD, add a new controller rather than a new action:

```ruby
# Instead of orders_controller#cancel, create:
# app/controllers/order_cancellations_controller.rb
class OrderCancellationsController < ApplicationController
  def create
    @order = Current.user.orders.find(params[:order_id])
    result = Orders::CancelService.call(@order, current_user)

    if result.success?
      redirect_to @order, notice: "Order cancelled."
    else
      redirect_to @order, alert: result.error
    end
  end
end

# config/routes.rb
resources :orders do
  resource :cancellation, only: [:create]
end
```

## Why This Is Good

- **Readable at a glance.** A new developer can open any controller and understand what every endpoint does in seconds. There's no business logic to parse — just HTTP flow.
- **Testable via request specs.** Thin controllers are tested through HTTP (request specs), which tests the real behavior. No need for brittle controller unit tests.
- **Consistent across the team.** Every controller follows the same 5-line-action pattern. Code reviews are faster because the shape is predictable.
- **RESTful by design.** Adding new controllers instead of new actions keeps the app RESTful. `OrderCancellationsController#create` is clearer than `OrdersController#cancel`.
- **Forces good architecture.** When you can't put logic in the controller, you're forced to find the right home for it — service objects, models, form objects, or query objects.

## Anti-Pattern

A controller with business logic, conditional branching, direct mailer calls, and inline data transformations:

```ruby
class OrdersController < ApplicationController
  def create
    @order = Order.new(order_params)
    @order.user = current_user

    # Business logic in controller
    @order.line_items.each do |item|
      product = Product.find(item.product_id)
      if product.stock < item.quantity
        flash[:alert] = "#{product.name} only has #{product.stock} left"
        render :new and return
      end
      item.unit_price = product.price
      item.total = product.price * item.quantity
    end

    @order.subtotal = @order.line_items.sum(&:total)
    @order.tax = @order.subtotal * 0.08
    @order.total = @order.subtotal + @order.tax

    if current_user.loyalty_points >= 100
      discount = (@order.total * 0.1).round(2)
      @order.discount = discount
      @order.total -= discount
      current_user.update(loyalty_points: current_user.loyalty_points - 100)
    end

    if @order.save
      @order.line_items.each do |item|
        product = Product.find(item.product_id)
        product.update!(stock: product.stock - item.quantity)
      end
      OrderMailer.confirmation(@order).deliver_later
      AdminMailer.new_order(@order).deliver_later if @order.total > 500
      redirect_to @order, notice: "Order placed!"
    else
      render :new
    end
  end
end
```

## Why This Is Bad

- **50+ lines for one action.** A developer has to read the entire method to understand what creating an order involves. The HTTP concerns (params, render, redirect) are buried among price calculations and stock updates.
- **Untestable in isolation.** To test order creation you must make HTTP requests, set up products with stock levels, loyalty points, and assert mailer deliveries — all in one test.
- **Logic is trapped.** When you need to create orders from an API endpoint, a Sidekiq job, or the console, you can't. The logic is locked inside an HTTP controller action.
- **Multiple responsibilities.** This action validates stock, calculates prices, applies discounts, manages loyalty points, updates inventory, and sends emails. Changing any one of these risks breaking the others.
- **Missing status codes.** The failure case renders `:new` without `status: :unprocessable_entity`, which breaks Turbo and returns 200 on validation failure.

## When To Apply

Always. Every Rails controller should follow skinny principles. The question isn't "should this controller be skinny?" — it's "where does the extracted logic go?"

- Simple CRUD (save one record, no side effects) → logic stays in the model
- Complex creation/updates (multiple models, side effects) → service object
- Complex validations (virtual attributes, multi-model validation) → form object
- Complex queries (reporting, search, filtering) → query object
- Shared controller behavior (auth, pagination, error handling) → controller concern

## When NOT To Apply

There is no case where a fat controller is the right choice. However, there are cases where extracting logic is premature:

- A 3-line create action that saves a record and redirects does NOT need a service object. The controller is already skinny.
- Simple `before_action` callbacks for setting records are fine in the controller. They don't need extraction.
- Standard `params.require().permit()` belongs in the controller, not in a separate class (unless the params logic itself is complex — then use a form object).

## Edge Cases

**The action is 8 lines but all the logic is param handling:**
That's a sign you need a form object, not a service object. If you're transforming, nesting, or conditionally including params, extract to a form object.

**You need to return different formats (HTML, JSON, CSV):**
Use `respond_to` blocks in the controller — format selection IS an HTTP concern. But keep the data preparation in a service or query object.

```ruby
def index
  @orders = Orders::SearchQuery.call(search_params)
  respond_to do |format|
    format.html
    format.json { render json: OrderSerializer.new(@orders) }
    format.csv { send_data Orders::CsvExporter.call(@orders), filename: "orders.csv" }
  end
end
```

**The team uses `before_action` for everything:**
Before actions are good for record loading and auth checks. They're bad for business logic. If a before action does more than `set_X` or `authorize_X`, it's hiding complexity in the wrong place.
