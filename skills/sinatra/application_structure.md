# Sinatra: Application Structure

## Pattern

Sinatra apps should be structured for clarity and growth. Small apps can use a single file. Anything beyond a prototype should use the modular style (`Sinatra::Base` subclass) with extracted helpers, services, and a clear directory layout.

### Single-File (Prototypes Only)

```ruby
# app.rb
require "sinatra"
require "json"

get "/health" do
  content_type :json
  { status: "ok", timestamp: Time.now.iso8601 }.to_json
end

get "/orders/:id" do
  order = Order.find(params[:id])
  halt 404, { error: "Not found" }.to_json unless order

  content_type :json
  order.to_json
end
```

### Modular Style (Recommended)

```
my_app/
├── Gemfile
├── config.ru
├── config/
│   ├── database.yml
│   └── environment.rb
├── app/
│   ├── api.rb              # Main Sinatra app
│   ├── routes/
│   │   ├── orders.rb
│   │   ├── users.rb
│   │   └── health.rb
│   ├── models/
│   │   ├── order.rb
│   │   └── user.rb
│   ├── services/
│   │   └── orders/
│   │       └── create_service.rb
│   └── helpers/
│       ├── auth_helper.rb
│       └── json_helper.rb
├── db/
│   └── migrate/
├── test/
│   ├── test_helper.rb
│   ├── routes/
│   │   └── orders_test.rb
│   └── services/
│       └── orders/
│           └── create_service_test.rb
└── Rakefile
```

```ruby
# config.ru
require_relative "config/environment"
run MyApp::Api
```

```ruby
# config/environment.rb
require "bundler/setup"
Bundler.require(:default, ENV.fetch("RACK_ENV", "development").to_sym)

require "sinatra/base"
require "sinatra/json"
require "sinatra/activerecord"

# Load app files
Dir[File.join(__dir__, "..", "app", "models", "*.rb")].each { |f| require f }
Dir[File.join(__dir__, "..", "app", "services", "**", "*.rb")].each { |f| require f }
Dir[File.join(__dir__, "..", "app", "helpers", "*.rb")].each { |f| require f }

require_relative "../app/api"
Dir[File.join(__dir__, "..", "app", "routes", "*.rb")].each { |f| require f }
```

```ruby
# app/api.rb
module MyApp
  class Api < Sinatra::Base
    register Sinatra::ActiveRecordExtension

    # Configuration
    configure do
      set :database_file, "config/database.yml"
      set :show_exceptions, false
    end

    configure :development do
      set :show_exceptions, :after_handler
    end

    # Middleware
    use Rack::JSONBodyParser

    # Global helpers
    helpers AuthHelper
    helpers JsonHelper

    # Error handling
    error ActiveRecord::RecordNotFound do
      halt 404, json_error("Not found")
    end

    error ActiveRecord::RecordInvalid do |e|
      halt 422, json_error("Validation failed", details: e.record.errors.full_messages)
    end

    error do |e|
      logger.error("#{e.class}: #{e.message}")
      halt 500, json_error("Internal server error")
    end
  end
end
```

```ruby
# app/helpers/auth_helper.rb
module AuthHelper
  def authenticate!
    token = request.env["HTTP_AUTHORIZATION"]&.delete_prefix("Bearer ")
    halt 401, json_error("Unauthorized") unless token

    @current_user = User.find_by_api_token(token)
    halt 401, json_error("Invalid token") unless @current_user
  end

  def current_user
    @current_user
  end
end

# app/helpers/json_helper.rb
module JsonHelper
  def json_response(data, status: 200)
    content_type :json
    halt status, data.to_json
  end

  def json_error(message, status: nil, details: nil)
    content_type :json
    body = { error: message }
    body[:details] = details if details
    body.to_json
  end
end
```

```ruby
# app/routes/orders.rb
module MyApp
  class Api
    # Routes grouped by resource
    before "/orders*" do
      authenticate!
    end

    get "/orders" do
      orders = current_user.orders.order(created_at: :desc)
      json_response(orders: orders.map(&:as_json))
    end

    get "/orders/:id" do
      order = current_user.orders.find(params[:id])
      json_response(order: order.as_json)
    end

    post "/orders" do
      result = Orders::CreateService.call(parsed_body, current_user)

      if result.success?
        json_response({ order: result.order.as_json }, status: 201)
      else
        halt 422, json_error("Creation failed", details: result.errors)
      end
    end

    delete "/orders/:id" do
      order = current_user.orders.find(params[:id])
      order.destroy!
      json_response({ deleted: true })
    end

    private

    def parsed_body
      JSON.parse(request.body.read, symbolize_names: true)
    rescue JSON::ParserError
      halt 400, json_error("Invalid JSON")
    end
  end
end
```

## Why This Is Good

- **Modular `Sinatra::Base` subclass.** The app is a class, not a script. It can be tested, mounted in Rack, and composed with other apps.
- **Routes in separate files.** Each resource has its own file. Adding a new resource means adding a new file, not editing a growing monolith.
- **Extracted helpers.** Auth and JSON helpers are reusable modules, not inline code in every route.
- **Centralized error handling.** `error ActiveRecord::RecordNotFound` handles 404s globally. No `begin/rescue` in every route.
- **Same service object pattern as Rails.** `Orders::CreateService.call(params, user)` works identically whether it's called from a Sinatra route or a Rails controller.

## Anti-Pattern

A single-file Sinatra app that grows into a 500-line monster:

```ruby
# BAD: Everything in one file
require "sinatra"
require "json"

# 50 lines of config
# 30 lines of helpers
# 100 lines of order routes
# 100 lines of user routes
# 80 lines of auth routes
# 50 lines of error handling
# 90 lines of inline business logic
```

## When To Apply

- **Every Sinatra app beyond a prototype.** The modular structure takes 10 minutes to set up and prevents every future headache.
- **API services.** Sinatra is excellent for focused, single-purpose APIs (webhook receivers, microservices, lightweight proxies).
- **When Rails is too heavy.** Sinatra boots in milliseconds, has minimal dependencies, and is perfect for small services.

## When NOT To Apply

- **If you need forms, views, sessions, mailers, background jobs, and admin panels.** Use Rails. Sinatra can do all of these but you'll end up rebuilding half of Rails.
- **If the app will grow to 50+ routes.** Sinatra's simplicity becomes a liability at scale. Consider Rails or Hanami.
