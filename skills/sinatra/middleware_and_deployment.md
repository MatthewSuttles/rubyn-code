# Sinatra: Middleware, Configuration, and Deployment

## Pattern

Sinatra apps are Rack apps. Use Rack middleware for cross-cutting concerns, environment-specific configuration for different stages, and standard deployment patterns for production.

### Middleware Stack

```ruby
# app/api.rb
module MyApp
  class Api < Sinatra::Base
    # Request/Response middleware
    use Rack::JSONBodyParser                    # Parse JSON bodies into params
    use Rack::Cors do                            # CORS for API clients
      allow do
        origins "*"
        resource "/api/*", headers: :any, methods: [:get, :post, :put, :delete]
      end
    end

    # Custom middleware
    use RequestLogger                            # Log every request
    use RateLimiter, limit: 100, period: 60      # 100 req/min
  end
end
```

```ruby
# app/middleware/request_logger.rb
class RequestLogger
  def initialize(app)
    @app = app
    @logger = Logger.new($stdout)
  end

  def call(env)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, headers, body = @app.call(env)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start

    @logger.info("#{env['REQUEST_METHOD']} #{env['PATH_INFO']} → #{status} (#{(elapsed * 1000).round}ms)")

    [status, headers, body]
  end
end
```

```ruby
# app/middleware/rate_limiter.rb
class RateLimiter
  def initialize(app, limit: 60, period: 60)
    @app = app
    @limit = limit
    @period = period
    @store = {}  # Use Redis in production
  end

  def call(env)
    key = client_key(env)
    count = increment(key)

    if count > @limit
      [429, { "Content-Type" => "application/json", "Retry-After" => @period.to_s },
       ['{"error":"Rate limited"}']]
    else
      @app.call(env)
    end
  end

  private

  def client_key(env)
    ip = env["HTTP_X_FORWARDED_FOR"]&.split(",")&.first || env["REMOTE_ADDR"]
    token = env["HTTP_AUTHORIZATION"]&.split(" ")&.last
    "rate:#{token || ip}:#{(Time.now.to_i / @period)}"
  end

  def increment(key)
    @store[key] = (@store[key] || 0) + 1
  end
end
```

### Environment Configuration

```ruby
# app/api.rb
module MyApp
  class Api < Sinatra::Base
    configure do
      set :root, File.dirname(__FILE__)
      set :views, File.join(root, "views")
      set :public_folder, File.join(root, "..", "public")

      # Don't show raw errors to users
      set :show_exceptions, false
      set :raise_errors, false

      enable :logging
    end

    configure :development do
      set :show_exceptions, :after_handler
      enable :reloader  # Reloads code on changes (with sinatra-contrib)
    end

    configure :test do
      set :raise_errors, true  # Let errors propagate to tests
    end

    configure :production do
      enable :logging

      # Force SSL
      use Rack::SslEnforcer if ENV["FORCE_SSL"]
    end
  end
end
```

### Database Setup (ActiveRecord or Sequel)

```ruby
# With sinatra-activerecord gem
# Gemfile
gem "sinatra-activerecord"
gem "pg"

# config/database.yml
development:
  adapter: postgresql
  database: my_app_development

test:
  adapter: postgresql
  database: my_app_test

production:
  url: <%= ENV["DATABASE_URL"] %>

# Rakefile
require_relative "config/environment"
require "sinatra/activerecord/rake"

# Now you get: rake db:create, db:migrate, db:seed, etc.
```

```ruby
# With Sequel (lightweight alternative)
# Gemfile
gem "sequel"
gem "pg"

# config/environment.rb
DB = Sequel.connect(ENV.fetch("DATABASE_URL", "postgres://localhost/my_app_dev"))
Sequel.extension :migration

# db/migrate/001_create_orders.rb
Sequel.migration do
  change do
    create_table(:orders) do
      primary_key :id
      String :reference, null: false, unique: true
      Integer :total, null: false
      String :status, default: "pending"
      DateTime :created_at
      DateTime :updated_at
    end
  end
end
```

### Deployment (Puma)

```ruby
# config/puma.rb
workers ENV.fetch("WEB_CONCURRENCY", 2).to_i
threads_count = ENV.fetch("MAX_THREADS", 5).to_i
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)
environment ENV.fetch("RACK_ENV", "development")

preload_app!
```

```ruby
# Procfile (for Heroku/DigitalOcean App Platform)
web: bundle exec puma -C config/puma.rb

# Docker
FROM ruby:3.3-slim
WORKDIR /app
COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test
COPY . .
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

## Why This Is Good

- **Middleware is composable.** Each middleware handles one concern: logging, CORS, rate limiting, SSL. Stack them in any order.
- **Same Rack ecosystem as Rails.** Rack::Cors, Rack::Attack, and other middleware work identically in Sinatra and Rails.
- **Lightweight deployment.** A Sinatra app starts in milliseconds and uses ~30MB of RAM. Perfect for microservices and sidecar APIs.
- **Standard tooling.** Puma, Procfile, Docker — the same deployment stack as Rails. No special Sinatra knowledge needed.

## When To Choose Sinatra

- **Focused API services** — webhook receivers, proxy APIs, embedding service wrappers
- **Microservices** — small, single-purpose services with 5-15 endpoints
- **Internal tools** — health dashboards, admin APIs, CLI backend services
- **When boot time matters** — Lambda functions, short-lived containers

## When To Choose Rails Instead

- **Full-stack web apps** — forms, views, sessions, asset pipeline, mailers
- **Complex data models** — 20+ tables with associations, migrations, seeds
- **Team projects** — Rails conventions mean less decision-making and easier onboarding
- **Rapid prototyping** — Rails generators and scaffolds are faster for CRUD
