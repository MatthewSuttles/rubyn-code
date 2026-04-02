# Rails: Service Object Extraction

## Pattern

Extract business logic from controllers into service objects when the action does more than receive params and persist a single record.

Service objects live in `app/services/`, namespaced by resource. They have a single public class method `.call` that returns a result object.

```ruby
# app/services/orders/create_service.rb
module Orders
  class CreateService
    def self.call(params, user)
      new(params, user).call
    end

    def initialize(params, user)
      @params = params
      @user = user
    end

    def call
      order = @user.orders.build(@params)

      unless inventory_available?(order)
        order.errors.add(:base, "Insufficient inventory")
        return Result.new(success: false, order: order)
      end

      if order.save
        send_confirmation(order)
        notify_warehouse(order)
        Result.new(success: true, order: order)
      else
        Result.new(success: false, order: order)
      end
    end

    private

    def inventory_available?(order)
      order.line_items.all? { |item| item.product.stock >= item.quantity }
    end

    def send_confirmation(order)
      OrderMailer.confirmation(order).deliver_later
    end

    def notify_warehouse(order)
      WarehouseNotificationJob.perform_later(order.id)
    end

    Result = Struct.new(:success, :order, keyword_init: true) do
      alias_method :success?, :success
    end
  end
end
```

The controller becomes a thin delegation layer:

```ruby
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def create
    result = Orders::CreateService.call(order_params, current_user)

    if result.success?
      redirect_to result.order, notice: "Order placed successfully."
    else
      @order = result.order
      render :new, status: :unprocessable_entity
    end
  end

  private

  def order_params
    params.require(:order).permit(:shipping_address, line_items_attributes: [:product_id, :quantity])
  end
end
```

## Why This Is Good

- **Testable in isolation.** The service object can be tested without routing, request/response cycles, or controller setup. Pass in params and a user, assert the result.
- **Single responsibility.** The controller handles HTTP concerns (params, redirects, status codes). The service handles business logic (validation, persistence, side effects).
- **Reusable.** When the same order creation logic is needed from an API endpoint, a Sidekiq job, or a rake task, call the same service. No duplication.
- **Readable.** A 5-line controller action tells you instantly what happens. The service object's private methods read like a checklist of the business process.
- **Debuggable.** When order creation breaks, you look at one file — the service. Not a 40-line controller action mixed with HTTP logic.

## Anti-Pattern

A controller action that handles business logic, persistence, mailer calls, and external notifications directly:

```ruby
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def create
    @order = current_user.orders.build(order_params)

    @order.line_items.each do |item|
      if item.product.stock < item.quantity
        @order.errors.add(:base, "#{item.product.name} is out of stock")
        render :new, status: :unprocessable_entity
        return
      end
    end

    if @order.save
      @order.line_items.each do |item|
        item.product.update!(stock: item.product.stock - item.quantity)
      end

      OrderMailer.confirmation(@order).deliver_later

      payload = { order_id: @order.id, items: @order.line_items.map(&:id) }
      WarehouseNotificationJob.perform_later(payload.to_json)

      if @order.total > 1000
        HighValueOrderNotificationJob.perform_later(@order.id)
      end

      redirect_to @order, notice: "Order placed successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

## Why This Is Bad

- **Untestable without full stack.** Testing this requires building a request, setting up authentication, creating products with stock, and asserting redirects — all to test business logic that has nothing to do with HTTP.
- **Impossible to reuse.** When you need to create orders from an API controller, you copy-paste this logic. When the logic changes, you update it in two places (or forget one).
- **Hard to read.** A developer looking at this action has to mentally separate "what's HTTP" from "what's business logic" from "what's side effects." At 30+ lines, that takes real effort.
- **Fragile.** Stock decrementation, mailer calls, and warehouse notifications are scattered in the controller. Missing one in a new code path causes inventory errors or silent failures.
- **Violates SRP.** The controller is handling params, validation, persistence, stock management, email, background jobs, and conditional notifications. That's 7 responsibilities in one method.

## When To Apply

Extract to a service object when ANY of these are true:

- The action exceeds **8 lines** of logic (excluding param handling and response rendering)
- The action touches **2 or more models** (e.g., creates an order AND updates product stock)
- The action has **side effects** beyond persistence — sending emails, enqueuing jobs, calling external APIs, publishing events
- The **same business logic** is needed in more than one place (API controller, background job, rake task, console)
- The action contains **conditional business logic** (if order > $1000, do X)

## When NOT To Apply

Do NOT extract to a service object when:

- The action is **simple CRUD** — receives params, saves one record, responds. A 4-line create action does not need a service object. The overhead of an extra file and class adds complexity without benefit.
- The action only **reads data** — index and show actions that query and render rarely need services. Use scopes on the model or query objects instead.
- You're extracting **just to extract**. If the service object would contain 3 lines that mirror what the controller already does, it's not adding value.

```ruby
# This does NOT need a service object. Leave it in the controller.
def create
  @comment = @post.comments.build(comment_params)
  @comment.user = current_user

  if @comment.save
    redirect_to @post, notice: "Comment added."
  else
    render :show, status: :unprocessable_entity
  end
end
```

## Edge Cases

**The action is 10 lines but only touches one model:**
Look at what those lines do. If it's complex validation logic, consider a form object instead. If it's complex querying, consider a query object. Service objects are best for multi-step processes with side effects.

**The service object would only be called from one place:**
That's fine. Single-use services are still valuable for testability and readability. The reuse benefit is a bonus, not a requirement.

**The team uses `interactor` or `dry-transaction` gems:**
Follow the team's established pattern. If they use interactors, write an interactor. Rubyn adapts to the project's conventions (detected via codebase memory), not the other way around.

**The existing codebase has no `app/services/` directory:**
Create it. This is a standard Rails convention even though Rails doesn't generate it by default. Place the service at `app/services/{resource}/{action}_service.rb`.
