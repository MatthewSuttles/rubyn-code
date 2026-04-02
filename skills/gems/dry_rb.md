# Gems: dry-rb Ecosystem

## Pattern

The dry-rb family provides standalone, composable libraries for validation, types, dependency injection, and functional patterns. They're popular in non-Rails Ruby projects and in Rails apps that want more rigor than ActiveModel provides.

### dry-validation (Schema Validation)

```ruby
# Gemfile
gem "dry-validation", "~> 1.10"

# app/contracts/order_contract.rb
class OrderContract < Dry::Validation::Contract
  params do
    required(:shipping_address).filled(:string)
    required(:line_items).array(:hash) do
      required(:product_id).filled(:integer)
      required(:quantity).filled(:integer, gt?: 0)
    end
    optional(:notes).maybe(:string)
    optional(:discount_code).maybe(:string, max_size?: 20)
  end

  rule(:line_items) do
    key.failure("must have at least one item") if values[:line_items].empty?
  end

  rule(:discount_code) do
    if values[:discount_code] && !Discount.active.exists?(code: values[:discount_code])
      key.failure("is not a valid discount code")
    end
  end
end

# Usage
contract = OrderContract.new
result = contract.call(params)

if result.success?
  # result.to_h contains validated, coerced data
  Orders::CreateService.call(result.to_h, current_user)
else
  # result.errors.to_h contains error messages by field
  # => { line_items: ["must have at least one item"] }
  render json: { errors: result.errors.to_h }, status: :unprocessable_entity
end
```

### dry-types (Type System)

```ruby
# Gemfile
gem "dry-types", "~> 1.7"

# app/types.rb
module Types
  include Dry.Types()

  Email = Types::String.constrained(format: URI::MailTo::EMAIL_REGEXP)
  PositiveMoney = Types::Coercible::Integer.constrained(gteq: 0)
  Status = Types::String.enum("pending", "confirmed", "shipped", "delivered", "cancelled")
  CreditAmount = Types::Coercible::Integer.constrained(gteq: 1, lteq: 10_000)
end

# Usage — type checking and coercion
Types::Email["alice@example.com"]  # => "alice@example.com"
Types::Email["not-an-email"]        # => Dry::Types::ConstraintError

Types::PositiveMoney[1999]          # => 1999
Types::PositiveMoney[-5]            # => Dry::Types::ConstraintError

Types::Status["pending"]            # => "pending"
Types::Status["invalid"]            # => Dry::Types::ConstraintError
```

### dry-monads (Result Type / Railway Programming)

```ruby
# Gemfile
gem "dry-monads", "~> 1.6"

# app/services/orders/create_service.rb
require "dry/monads"

class Orders::CreateService
  include Dry::Monads[:result, :do]

  def call(params, user)
    validated = yield validate(params)
    order = yield create_order(validated, user)
    yield charge_payment(order)
    yield send_confirmation(order)

    Success(order)
  end

  private

  def validate(params)
    result = OrderContract.new.call(params)
    result.success? ? Success(result.to_h) : Failure(result.errors.to_h)
  end

  def create_order(params, user)
    order = user.orders.create(params)
    order.persisted? ? Success(order) : Failure(order.errors.full_messages)
  end

  def charge_payment(order)
    result = Payments::ChargeService.call(order)
    result.success? ? Success(result) : Failure("Payment failed: #{result.error}")
  end

  def send_confirmation(order)
    OrderMailer.confirmation(order).deliver_later
    Success(true)
  end
end

# Controller — pattern match on the result
result = Orders::CreateService.new.call(params, current_user)

case result
in Dry::Monads::Success(order)
  redirect_to order, notice: "Order placed"
in Dry::Monads::Failure(errors) if errors.is_a?(Hash)
  @errors = errors
  render :new, status: :unprocessable_entity
in Dry::Monads::Failure(message)
  flash.now[:alert] = message
  render :new, status: :unprocessable_entity
end
```

The `yield` keyword with `do` notation short-circuits on `Failure` — if `validate` returns `Failure`, the remaining steps never execute. This is the "railway" pattern: success continues down the track, failure jumps to the error track immediately.

### dry-struct (Typed Data Objects)

```ruby
# Gemfile
gem "dry-struct", "~> 1.6"

class OrderRequest < Dry::Struct
  attribute :shipping_address, Types::String
  attribute :line_items, Types::Array.of(LineItemRequest)
  attribute :discount_code, Types::String.optional
  attribute :notes, Types::String.optional.default(nil)
end

class LineItemRequest < Dry::Struct
  attribute :product_id, Types::Coercible::Integer
  attribute :quantity, Types::Coercible::Integer.constrained(gteq: 1)
end

# Construction validates types automatically
request = OrderRequest.new(
  shipping_address: "123 Main St",
  line_items: [{ product_id: "42", quantity: "2" }],  # Strings coerced to integers
  discount_code: nil
)

request.line_items.first.product_id  # => 42 (Integer, coerced from String)
request.line_items.first.quantity    # => 2 (Integer)
```

## Why This Is Good

- **dry-validation separates validation from models.** Complex validations (cross-field, external lookups, nested structures) have a dedicated home that's not the ActiveRecord model.
- **dry-types catch type errors at boundaries.** Instead of `NoMethodError: undefined method 'to_i' for nil` buried in a service, you get `Dry::Types::ConstraintError` at the entry point.
- **dry-monads make error flow explicit.** Every step returns `Success` or `Failure`. The `do` notation short-circuits on failure. No hidden exception paths, no nil returns.
- **Composable and standalone.** Each dry-rb gem works independently. Use dry-validation without dry-monads, or dry-types without dry-struct.

## When To Apply

- **Complex validation beyond what ActiveModel handles.** Nested params, cross-field rules, external lookups, multi-step validation.
- **Non-Rails Ruby projects.** dry-rb is framework-agnostic. Perfect for Sinatra apps, plain Ruby services, and gems.
- **Teams that want explicit error handling.** dry-monads forces every failure path to be handled. Nothing slips through silently.
- **API input validation.** dry-validation is excellent for validating JSON API payloads before they touch ActiveRecord.

## When NOT To Apply

- **Simple Rails apps with standard validations.** `validates :name, presence: true` is fine. Don't add dry-validation for what ActiveModel already handles.
- **The team is unfamiliar with functional patterns.** dry-monads' `Success`/`Failure`/`yield` pattern has a learning curve. If the team isn't bought in, it creates friction.
- **Mixing dry-rb and ActiveModel validations.** Pick one approach per layer. Don't validate params with dry-validation AND re-validate in the model with ActiveModel — you'll get confused about which errors come from where.
- **Small projects.** The dry-rb gems add dependencies and concepts. For a 10-controller Rails app, they're overkill.
