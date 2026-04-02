# Ruby: Result Objects

## Pattern

Instead of returning mixed types (record or nil, true or false) or raising exceptions for expected failures, return a Result object that explicitly represents success or failure. The caller inspects the result instead of rescuing exceptions.

```ruby
# Simple Result using Data.define (Ruby 3.2+)
Result = Data.define(:success, :value, :error) do
  def success? = success
  def failure? = !success

  def self.success(value)
    new(success: true, value: value, error: nil)
  end

  def self.failure(error)
    new(success: false, value: nil, error: error)
  end
end
```

```ruby
# Service object using Result
class Orders::CreateService
  def self.call(params, user)
    order = user.orders.build(params)

    unless order.valid?
      return Result.failure(order.errors.full_messages.join(", "))
    end

    ActiveRecord::Base.transaction do
      order.save!
      OrderConfirmationJob.perform_later(order.id)
    end

    Result.success(order)
  rescue ActiveRecord::RecordInvalid => e
    Result.failure(e.message)
  end
end

# The caller handles both cases explicitly — no rescue needed
result = Orders::CreateService.call(params, current_user)

if result.success?
  redirect_to result.value, notice: "Order created."
else
  flash.now[:alert] = result.error
  render :new, status: :unprocessable_entity
end
```

### Result with Error Codes

```ruby
# More structured for API responses
Result = Data.define(:success, :value, :error, :error_code) do
  def success? = success
  def failure? = !success

  def self.success(value)
    new(success: true, value: value, error: nil, error_code: nil)
  end

  def self.failure(error, code: :unknown)
    new(success: false, value: nil, error: error, error_code: code)
  end
end

class Credits::DeductionService
  def self.call(user, amount)
    if user.credit_balance < amount
      return Result.failure("Insufficient credits. Balance: #{user.credit_balance}, needed: #{amount}",
                            code: :insufficient_credits)
    end

    if user.suspended?
      return Result.failure("Account suspended", code: :account_suspended)
    end

    user.deduct_credits!(amount)
    Result.success(user.credit_balance)
  end
end

# API controller maps error codes to HTTP statuses
result = Credits::DeductionService.call(current_user, credits_needed)

unless result.success?
  status = case result.error_code
           when :insufficient_credits then :payment_required
           when :account_suspended then :forbidden
           else :unprocessable_entity
           end
  render json: { error: result.error }, status: status
  return
end
```

### Result with Struct (Pre-Ruby 3.2)

```ruby
Result = Struct.new(:success, :value, :error, keyword_init: true) do
  def success? = success
  def failure? = !success

  def self.success(value)
    new(success: true, value: value)
  end

  def self.failure(error)
    new(success: false, error: error)
  end
end
```

### Chaining Results (Railway-Oriented Programming)

```ruby
class Orders::CheckoutPipeline
  def self.call(params, user)
    validate(params)
      .then { |p| reserve_inventory(p) }
      .then { |reservation| charge_payment(user, reservation) }
      .then { |charge| create_order(user, params, charge) }
      .then { |order| send_notifications(order) }
  end

  private

  def self.validate(params)
    return Result.failure("Missing address") if params[:address].blank?
    Result.success(params)
  end

  def self.reserve_inventory(params)
    reservation = Inventory::Reserve.call(params[:items])
    reservation.success? ? Result.success(reservation) : Result.failure(reservation.error)
  end

  # Each step returns Result.success or Result.failure
  # .then only executes if the previous result was success
end

# Add .then to Result
Result = Data.define(:success, :value, :error) do
  def success? = success
  def failure? = !success

  def then
    return self if failure?
    yield(value)
  end

  def self.success(value) = new(success: true, value: value, error: nil)
  def self.failure(error) = new(success: false, value: nil, error: error)
end
```

## Why This Is Good

- **Explicit over implicit.** The return type tells you both success and failure are possible. No surprise `nil` returns or unexpected exceptions.
- **The caller decides how to handle failure.** A controller renders an error page. A background job retries. A CLI prints a message. The service doesn't dictate error handling.
- **No exceptions for expected failures.** "Insufficient credits" is not exceptional — it's a normal business outcome. Exceptions should be for unexpected failures (database down, network timeout).
- **Chainable.** `.then` enables railway-oriented programming where the pipeline short-circuits on the first failure.
- **Testable.** Assert `result.success?` and `result.value` — clean, specific, no `assert_raises` for business logic failures.

## Anti-Pattern

Mixed return types or exceptions for flow control:

```ruby
# BAD: Returns an Order on success, a String on failure
def create_order(params)
  order = Order.create!(params)
  order
rescue ActiveRecord::RecordInvalid => e
  e.message  # Returns a String — caller must check type
end

# BAD: Raises for expected business failures
def deduct_credits(user, amount)
  raise InsufficientCredits if user.balance < amount  # Expected outcome, not exceptional
  user.deduct!(amount)
end
```

## When To Apply

- **Every service object.** Services should return Results, not raise or return mixed types.
- **Operations with known failure modes.** Payment declined, insufficient credits, validation failed, rate limited — all expected outcomes.
- **Multi-step workflows.** Each step returns a Result. The pipeline short-circuits on failure.

## When NOT To Apply

- **Simple model methods.** `order.total` returns a number. It doesn't need a Result wrapper.
- **Truly exceptional failures.** Database connection lost, out of memory, unexpected nil — these should raise exceptions. They're not business outcomes.
- **Single-line lookups.** `User.find(id)` raising `RecordNotFound` is fine — it's the Rails convention and rescued at the controller level.
