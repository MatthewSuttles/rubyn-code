# Design Pattern: Factory Method

## Pattern

Define a method that creates objects without specifying the exact class. Let subclasses or configuration determine which class to instantiate. In Ruby, factories are often class methods, configuration hashes, or registry patterns rather than subclass hierarchies.

```ruby
# Factory method as a class method with registration
class Notifications::Factory
  REGISTRY = {}

  def self.register(channel, klass)
    REGISTRY[channel.to_sym] = klass
  end

  def self.build(channel, **options)
    klass = REGISTRY.fetch(channel.to_sym) do
      raise ArgumentError, "Unknown notification channel: #{channel}. Available: #{REGISTRY.keys.join(', ')}"
    end
    klass.new(**options)
  end
end

class Notifications::EmailNotifier
  def initialize(from: "noreply@rubyn.ai")
    @from = from
  end

  def deliver(user, message)
    NotificationMailer.notify(to: user.email, from: @from, body: message).deliver_later
  end
end
Notifications::Factory.register(:email, Notifications::EmailNotifier)

class Notifications::SmsNotifier
  def initialize(provider: :twilio)
    @provider = provider
  end

  def deliver(user, message)
    SmsClient.new(provider: @provider).send(user.phone, message.truncate(160))
  end
end
Notifications::Factory.register(:sms, Notifications::SmsNotifier)

# Usage — caller doesn't know or import the concrete class
notifier = Notifications::Factory.build(:email)
notifier.deliver(user, "Your order shipped!")

notifier = Notifications::Factory.build(:sms, provider: :vonage)
notifier.deliver(user, "Your order shipped!")
```

Factory method on a model — named constructors:

```ruby
class Order < ApplicationRecord
  def self.from_cart(cart, user:)
    new(
      user: user,
      shipping_address: user.default_address,
      line_items: cart.items.map { |item|
        LineItem.new(product: item.product, quantity: item.quantity, unit_price: item.product.price)
      }
    )
  end

  def self.from_api(params)
    new(
      user: User.find(params[:user_id]),
      shipping_address: params[:shipping_address],
      line_items: params[:items].map { |item|
        LineItem.new(product_id: item[:product_id], quantity: item[:quantity])
      }
    )
  end

  def self.reorder(previous_order)
    from_cart(
      OpenStruct.new(items: previous_order.line_items),
      user: previous_order.user
    )
  end
end

# Each factory method communicates intent and handles context-specific setup
order = Order.from_cart(shopping_cart, user: current_user)
order = Order.from_api(api_params)
order = Order.reorder(previous_order)
```

Configuration-driven factory:

```ruby
# Embedding client factory — environment determines the implementation
class Embeddings::ClientFactory
  def self.build
    case Rails.env
    when "production"
      Embeddings::HttpClient.new(base_url: ENV.fetch("EMBEDDING_SERVICE_URL"))
    when "test"
      Embeddings::FakeClient.new
    when "development"
      if ENV["EMBEDDING_SERVICE_URL"].present?
        Embeddings::HttpClient.new(base_url: ENV["EMBEDDING_SERVICE_URL"])
      else
        Embeddings::FakeClient.new
      end
    end
  end
end

# config/initializers/embeddings.rb
Rails.application.config.x.embedding_client = Embeddings::ClientFactory.build
```

## Why This Is Good

- **Decouples creation from use.** The code that uses a notifier doesn't need to know which concrete class to instantiate. It asks the factory for `:email` and gets back a ready-to-use object.
- **Named constructors are self-documenting.** `Order.from_cart(cart, user:)` tells you exactly what context the order is being created in. `Order.new(user: user, ...)` doesn't.
- **New types don't require modifying callers.** Adding a `PushNotifier` means registering it with the factory. Every caller that uses `Factory.build(:push)` works immediately.
- **Environment-aware factories centralize configuration.** One place decides that production uses the real embedding service and tests use a fake.

## When To Apply

- **Multiple types with the same interface.** Notification channels, payment processors, export formatters, AI model clients — any family of interchangeable implementations.
- **Complex construction.** When building an object requires 5+ lines of setup, configuration lookups, or conditional logic, wrap it in a factory method.
- **Named constructors for models.** When the same model is created from different sources (web form, API, CSV import) with different setup requirements.

## When NOT To Apply

- **Simple `new` calls.** `User.new(email: email, name: name)` doesn't need a factory. Factories solve complex or polymorphic construction, not all construction.
- **One implementation.** If there's only one notifier and will only ever be one, skip the factory. Direct instantiation is clearer.
- **Rails model `.create` with simple params.** Don't wrap `Order.create!(params)` in a factory just for abstraction. Use factories when there's actual construction complexity.

## Rails Example

```ruby
# Service object factory for AI interactions — selects strategy based on request type
class Ai::ServiceFactory
  SERVICES = {
    "refactor" => Ai::RefactorService,
    "review" => Ai::ReviewService,
    "explain" => Ai::ExplainService,
    "generate" => Ai::GenerateService,
    "debug" => Ai::DebugService
  }.freeze

  def self.build(request_type, **dependencies)
    service_class = SERVICES.fetch(request_type) do
      raise ArgumentError, "Unknown AI request type: #{request_type}"
    end
    service_class.new(**dependencies)
  end
end

# API controller uses the factory
class Api::V1::AiController < Api::V1::BaseController
  def create
    service = Ai::ServiceFactory.build(
      params[:type],
      client: Rails.application.config.x.ai_client,
      pricing: current_pricing_strategy
    )
    result = service.call(params[:prompt], context: build_context)
    render json: result
  end
end
```
