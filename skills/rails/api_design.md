# Rails: API Design

## Pattern

Design APIs to be consistent, versioned, and self-documenting. Use Grape or Rails API mode with `jbuilder`/`jsonapi-serializer`. Follow RESTful conventions. Handle errors uniformly.

### API Controller Structure

```ruby
# app/controllers/api/v1/base_controller.rb
module Api
  module V1
    class BaseController < ActionController::API
      include Authenticatable
      include Paginatable
      include ErrorHandling

      before_action :authenticate!

      private

      def render_success(data, status: :ok, meta: {})
        response = { data: data }
        response[:meta] = meta if meta.present?
        render json: response, status: status
      end

      def render_created(data)
        render_success(data, status: :created)
      end

      def render_error(message, status:, details: nil)
        body = { error: { message: message } }
        body[:error][:details] = details if details
        render json: body, status: status
      end
    end
  end
end
```

```ruby
# app/controllers/api/v1/orders_controller.rb
module Api
  module V1
    class OrdersController < BaseController
      def index
        orders = paginate(current_user.orders.includes(:line_items).recent)

        render_success(
          orders.map { |o| OrderSerializer.new(o).as_json },
          meta: pagination_meta(orders)
        )
      end

      def show
        order = current_user.orders.find(params[:id])
        render_success(OrderSerializer.new(order).as_json)
      end

      def create
        result = Orders::CreateService.call(order_params.to_h, current_user)

        if result.success?
          render_created(OrderSerializer.new(result.order).as_json)
        else
          render_error("Validation failed", status: :unprocessable_entity,
            details: result.order.errors.full_messages)
        end
      end

      private

      def order_params
        params.require(:order).permit(:shipping_address, line_items: [:product_id, :quantity])
      end
    end
  end
end
```

### Consistent Error Responses

```ruby
# app/controllers/concerns/error_handling.rb
module ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from ActiveRecord::RecordNotFound do |e|
      render_error("Resource not found", status: :not_found)
    end

    rescue_from ActiveRecord::RecordInvalid do |e|
      render_error("Validation failed", status: :unprocessable_entity,
        details: e.record.errors.full_messages)
    end

    rescue_from ActionController::ParameterMissing do |e|
      render_error("Missing parameter: #{e.param}", status: :bad_request)
    end

    rescue_from Pundit::NotAuthorizedError do
      render_error("Forbidden", status: :forbidden)
    end
  end
end
```

### Serializers

```ruby
# app/serializers/order_serializer.rb
class OrderSerializer
  def initialize(order)
    @order = order
  end

  def as_json(*)
    {
      id: @order.id,
      reference: @order.reference,
      status: @order.status,
      total: @order.total,
      shipping_address: @order.shipping_address,
      line_items: @order.line_items.map { |li| LineItemSerializer.new(li).as_json },
      created_at: @order.created_at.iso8601,
      updated_at: @order.updated_at.iso8601
    }
  end
end
```

### Versioning

```ruby
# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :orders, only: [:index, :show, :create, :update, :destroy]
      resources :projects, only: [:index, :show, :create] do
        resources :embeddings, only: [:index, :create], controller: "project_embeddings"
      end
      namespace :ai do
        post :refactor
        post :review
        post :explain
      end
    end
  end
end
```

### Authentication

```ruby
# app/controllers/concerns/authenticatable.rb
module Authenticatable
  extend ActiveSupport::Concern

  private

  def authenticate!
    token = request.headers["Authorization"]&.delete_prefix("Bearer ")
    render_error("Unauthorized", status: :unauthorized) and return unless token

    api_key = ApiKey.active.find_by_token(token)
    render_error("Invalid API key", status: :unauthorized) and return unless api_key

    api_key.touch(:last_used_at)
    @current_user = api_key.user
  end

  def current_user
    @current_user
  end
end
```

## Why This Is Good

- **Consistent response shape.** Every success returns `{ data: ... }`. Every error returns `{ error: { message: ..., details: ... } }`. Clients parse responses predictably.
- **Versioned from day one.** `/api/v1/` allows breaking changes in v2 without breaking existing clients.
- **Centralized error handling.** `rescue_from` in a concern handles all common exceptions. No begin/rescue in every action.
- **Serializers control the API surface.** Only expose the fields you intend. Internal fields (password_digest, internal notes) never leak.
- **Pagination metadata in every list endpoint.** Clients always know total count, current page, and total pages.

## Anti-Pattern

Inconsistent responses, no versioning, and exposing model internals:

```ruby
# BAD: render model directly
def show
  render json: Order.find(params[:id])
  # Exposes EVERY column including internal fields
end

# BAD: inconsistent error formats
def create
  order = Order.create!(params)
  render json: order
rescue => e
  render json: { msg: e.message }, status: 500  # Different shape than other errors
end
```

## When To Apply

- **Every API.** Consistent structure, versioning, and error handling should be established in the first endpoint.
- **Even internal APIs.** Microservice-to-microservice APIs benefit from the same discipline. Future developers will thank you.
