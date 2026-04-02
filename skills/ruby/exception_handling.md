# Ruby: Exception Handling

## Pattern

Rescue specific exceptions. Define custom exception hierarchies for your domain. Never use bare `rescue`. Use `retry` with limits. Always clean up resources in `ensure`.

```ruby
# Define a custom exception hierarchy for your domain
module Rubyn
  class Error < StandardError; end

  class AuthenticationError < Error; end
  class InsufficientCreditsError < Error; end
  class RateLimitError < Error; end

  class ApiError < Error
    attr_reader :status_code, :response_body

    def initialize(message, status_code:, response_body: nil)
      @status_code = status_code
      @response_body = response_body
      super(message)
    end
  end
end
```

```ruby
# Rescue specific exceptions with appropriate handling
class Orders::CreateService
  def call
    order = build_order
    charge_payment(order)
    order.save!
    send_confirmation(order)
    Result.new(success: true, order: order)
  rescue Stripe::CardError => e
    # Specific: payment failed, tell the user
    Result.new(success: false, error: "Payment declined: #{e.message}")
  rescue Stripe::RateLimitError => e
    # Specific: transient, retry makes sense
    retry_or_fail(e)
  rescue ActiveRecord::RecordInvalid => e
    # Specific: validation failed
    Result.new(success: false, error: e.record.errors.full_messages.join(", "))
  rescue Rubyn::InsufficientCreditsError
    # Specific: domain error
    Result.new(success: false, error: "Insufficient credits")
  end
end
```

```ruby
# Retry pattern with exponential backoff and limit
def fetch_with_retry(url, max_retries: 3)
  retries = 0
  begin
    response = Faraday.get(url)
    raise Rubyn::ApiError.new("Server error", status_code: response.status) if response.status >= 500
    response
  rescue Faraday::TimeoutError, Rubyn::ApiError => e
    retries += 1
    raise if retries > max_retries

    sleep_time = (2**retries) + rand(0.0..0.5) # Exponential backoff with jitter
    Rails.logger.warn("Retry #{retries}/#{max_retries} after #{e.class}: sleeping #{sleep_time}s")
    sleep(sleep_time)
    retry
  end
end
```

```ruby
# Ensure for guaranteed cleanup
def process_file(path)
  file = File.open(path, "r")
  parse_contents(file.read)
rescue CSV::MalformedCSVError => e
  Rails.logger.error("Malformed CSV: #{e.message}")
  raise
ensure
  file&.close
end

# Better: use block form which handles cleanup automatically
def process_file(path)
  File.open(path, "r") do |file|
    parse_contents(file.read)
  end
rescue CSV::MalformedCSVError => e
  Rails.logger.error("Malformed CSV: #{e.message}")
  raise
end
```

## Why This Is Good

- **Specific rescues handle specific failures.** A `Stripe::CardError` gets a user-facing message. A `Stripe::RateLimitError` gets a retry. A bare `rescue` would handle both the same way — hiding the card error behind a generic "something went wrong."
- **Custom exceptions communicate domain intent.** `raise Rubyn::InsufficientCreditsError` is meaningful to anyone reading the code. `raise StandardError, "not enough credits"` is generic and uncatchable by type.
- **Exception hierarchies enable selective catching.** `rescue Rubyn::Error` catches all domain exceptions. `rescue Rubyn::AuthenticationError` catches only auth failures. The hierarchy gives callers the granularity they need.
- **Retry with backoff prevents cascading failures.** A transient network error triggers a retry with increasing delay, not an immediate failure or an infinite retry loop.
- **`ensure` guarantees cleanup.** File handles, database connections, and temporary resources are always released, even when an exception occurs.

## Anti-Pattern

Bare rescue, swallowed exceptions, and rescue-driven flow control:

```ruby
# BAD: Bare rescue catches EVERYTHING including SyntaxError, NoMemoryError
def create_order(params)
  order = Order.create!(params)
  charge_payment(order)
  order
rescue
  nil
end

# BAD: Rescuing Exception (catches system signals, memory errors)
begin
  dangerous_operation
rescue Exception => e
  log(e.message)
end

# BAD: Using exceptions for flow control
def find_user(email)
  User.find_by!(email: email)
rescue ActiveRecord::RecordNotFound
  User.create!(email: email, name: "New User")
end

# BAD: Swallowing exceptions silently
def send_notification(user)
  NotificationService.call(user)
rescue StandardError
  # silently ignore all errors
end
```

## Why This Is Bad

- **Bare `rescue` catches `StandardError` and all subclasses.** This includes `NoMethodError`, `TypeError`, `NameError` — real bugs in your code that should crash loudly, not be silently swallowed. You're hiding bugs, not handling errors.
- **Rescuing `Exception` catches signals.** `Interrupt` (Ctrl+C), `SignalException` (kill), `NoMemoryError`, and `SyntaxError` are all subclasses of `Exception`. Rescuing them makes your program unkillable and masks fatal errors.
- **Exceptions for flow control are slow and misleading.** `find_by!` + `rescue RecordNotFound` is 10-100x slower than `find_by` + `nil?` check. Exceptions should be exceptional — unexpected failures, not expected branches.
- **Silently swallowed exceptions are invisible bugs.** When `NotificationService.call` fails, nobody knows. The user doesn't get notified, no error is logged, no alert fires. The bug exists silently until someone investigates why notifications stopped.

## When To Apply

- **Always rescue specific exception classes.** Name the exception class you expect. If you can't name it, you don't understand the failure mode well enough to handle it.
- **Custom exceptions for domain errors.** If your application has distinct failure modes (insufficient credits, rate limited, invalid API key), define exceptions for them.
- **Retry for transient failures only.** Network timeouts, rate limits, and temporary server errors are retriable. Validation errors, authentication failures, and business logic violations are not.
- **`ensure` for any resource that must be cleaned up.** Files, sockets, database connections, temporary directories. Or better — use block form methods that handle cleanup automatically (`File.open { }`, `ActiveRecord::Base.transaction { }`).

## When NOT To Apply

- **Don't rescue in every method.** Let exceptions propagate to the appropriate handler. A service object should raise; the controller or error middleware catches and renders the appropriate response.
- **Don't define custom exceptions for one-off cases.** If an exception is only raised in one place and caught in one place, `StandardError` with a message is sufficient. Custom exceptions shine when the same error type is raised or caught in multiple places.
- **Don't retry non-transient errors.** Retrying a `Stripe::CardError` (card declined) will fail every time. Retrying a `Stripe::RateLimitError` (temporary) makes sense.

## Edge Cases

**Re-raising after logging:**
Use `raise` with no arguments to re-raise the current exception after logging it:

```ruby
rescue Rubyn::ApiError => e
  Rails.logger.error("API failed: #{e.message}")
  raise  # Re-raises the same exception with original backtrace
end
```

**Wrapping third-party exceptions:**
Convert external gem exceptions into your domain exceptions at the boundary:

```ruby
def fetch_data
  ExternalApi.get("/data")
rescue ExternalApi::Timeout => e
  raise Rubyn::ApiError.new("External service timed out", status_code: 504)
rescue ExternalApi::Unauthorized => e
  raise Rubyn::AuthenticationError, "Invalid external API credentials"
end
```

**Multiple rescue clauses — order matters:**
Ruby checks rescue clauses top to bottom. Put specific exceptions before general ones:

```ruby
rescue Stripe::CardError => e          # Specific first
  handle_card_error(e)
rescue Stripe::StripeError => e         # General parent second
  handle_stripe_error(e)
rescue StandardError => e               # Catch-all last
  handle_unexpected_error(e)
end
```

**Exception in `ensure`:**
If `ensure` raises an exception, it replaces the original exception. Keep `ensure` blocks simple and safe. Wrap cleanup in its own begin/rescue if it might fail.
