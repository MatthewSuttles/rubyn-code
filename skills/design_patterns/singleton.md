# Design Pattern: Singleton

## Pattern

Ensure a class has only one instance and provide a global point of access to it. Ruby provides a built-in `Singleton` module, but in practice you should almost always use module-level state or class methods instead.

### Ruby's Built-In Singleton

```ruby
require "singleton"

class AppConfig
  include Singleton

  attr_accessor :api_key, :environment, :log_level

  def initialize
    @environment = ENV.fetch("RACK_ENV", "development")
    @log_level = :info
  end
end

# Usage
AppConfig.instance.api_key = "sk-123"
AppConfig.instance.log_level  # => :info

# .new raises NoMethodError
AppConfig.new  # => NoMethodError: private method 'new' called
```

### Better Alternative: Module with State

```ruby
# More idiomatic Ruby — module with class-level state
module AppConfig
  class << self
    attr_accessor :api_key, :environment, :log_level

    def configure
      yield self if block_given?
    end

    def reset!
      @api_key = nil
      @environment = "development"
      @log_level = :info
    end
  end

  # Defaults
  self.environment = ENV.fetch("RACK_ENV", "development")
  self.log_level = :info
end

# Usage — cleaner, no .instance call
AppConfig.configure do |config|
  config.api_key = "sk-123"
  config.log_level = :debug
end

AppConfig.api_key  # => "sk-123"
```

### Thread-Safe Singleton (When You Actually Need One)

```ruby
class ConnectionPool
  include Singleton

  def initialize
    @mutex = Mutex.new
    @connections = []
    @max_size = 10
  end

  def checkout
    @mutex.synchronize do
      @connections.pop || create_connection
    end
  end

  def checkin(conn)
    @mutex.synchronize do
      @connections.push(conn) if @connections.size < @max_size
    end
  end

  private

  def create_connection
    DatabaseConnection.new
  end
end
```

## When To Apply

- **Connection pools.** A single pool managing shared resources across threads.
- **Configuration objects.** Global app configuration accessed everywhere (but prefer the module pattern above).
- **Caches.** A single in-memory cache shared across the application.
- **Logger instances.** One logger configured once, used everywhere.

## When NOT To Apply (Most of the Time)

- **Don't use Singleton as a global variable.** If you're using Singleton to share state between unrelated classes, you have a coupling problem. Pass dependencies explicitly.
- **Don't use Singleton in Rails.** Rails has `Rails.application.config`, `Rails.cache`, `Rails.logger`. Use those instead of rolling your own singletons.
- **Don't use Singleton for testability-killing global state.** Singletons persist across tests, causing test pollution. Module-level state with a `reset!` method is easier to test.
- **Prefer dependency injection.** Instead of `AppConfig.instance.api_key` deep inside a service, pass the API key as a constructor argument. This makes the dependency explicit and testable.

## Edge Cases

**Singleton + Threads:**
Ruby's `Singleton` module is thread-safe for instance creation. But the instance's mutable state is NOT thread-safe unless you add synchronization (`Mutex`).

**Testing Singletons:**
Always provide a `reset!` method:

```ruby
def teardown
  AppConfig.reset!
end
```

Without this, state leaks between tests and causes order-dependent failures.
