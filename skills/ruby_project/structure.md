# Ruby: Project Structure

## Pattern

Whether you're building a gem, a CLI tool, or a library, follow Ruby conventions for directory layout, naming, and require paths. Use Bundler's gem skeleton as the starting point.

### Standard Ruby Gem / Library Layout

```
my_gem/
├── lib/
│   ├── my_gem.rb              # Main entry point, requires sub-files
│   └── my_gem/
│       ├── version.rb
│       ├── configuration.rb
│       ├── client.rb
│       ├── models/
│       │   ├── order.rb
│       │   └── user.rb
│       └── errors.rb
├── test/                       # or spec/
│   ├── test_helper.rb
│   ├── my_gem/
│   │   ├── client_test.rb
│   │   └── models/
│   │       └── order_test.rb
│   └── integration/
│       └── api_test.rb
├── bin/
│   └── my_gem                  # CLI executable (if applicable)
├── Gemfile
├── Rakefile
├── my_gem.gemspec
├── README.md
├── LICENSE.txt
└── CHANGELOG.md
```

### The Main Entry Point

```ruby
# lib/my_gem.rb
require_relative "my_gem/version"
require_relative "my_gem/configuration"
require_relative "my_gem/errors"
require_relative "my_gem/client"

module MyGem
  class << self
    attr_accessor :configuration

    def configure
      self.configuration ||= Configuration.new
      yield(configuration) if block_given?
    end

    def reset!
      self.configuration = Configuration.new
    end
  end
end
```

```ruby
# lib/my_gem/version.rb
module MyGem
  VERSION = "1.0.0"
end
```

```ruby
# lib/my_gem/configuration.rb
module MyGem
  class Configuration
    attr_accessor :api_key, :base_url, :timeout, :logger

    def initialize
      @base_url = "https://api.example.com"
      @timeout = 30
      @logger = Logger.new($stdout)
    end
  end
end
```

```ruby
# lib/my_gem/errors.rb
module MyGem
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class RateLimitError < Error; end
  class ApiError < Error
    attr_reader :status, :body
    def initialize(message, status:, body: nil)
      @status = status
      @body = body
      super(message)
    end
  end
end
```

```ruby
# lib/my_gem/client.rb
require "faraday"
require "json"

module MyGem
  class Client
    def initialize(api_key: nil, base_url: nil)
      config = MyGem.configuration || Configuration.new
      @api_key = api_key || config.api_key
      @base_url = base_url || config.base_url
      @conn = build_connection
    end

    def get_order(id)
      response = @conn.get("/orders/#{id}")
      handle_response(response)
    end

    def create_order(params)
      response = @conn.post("/orders", params.to_json)
      handle_response(response)
    end

    private

    def build_connection
      Faraday.new(url: @base_url) do |f|
        f.request :json
        f.response :json
        f.headers["Authorization"] = "Bearer #{@api_key}"
        f.options.timeout = MyGem.configuration&.timeout || 30
      end
    end

    def handle_response(response)
      case response.status
      when 200..299 then response.body
      when 401 then raise AuthenticationError, "Invalid API key"
      when 429 then raise RateLimitError, "Rate limited"
      else raise ApiError.new("API error", status: response.status, body: response.body)
      end
    end
  end
end
```

### Usage

```ruby
# Configuration (once, at boot)
MyGem.configure do |config|
  config.api_key = ENV["MY_GEM_API_KEY"]
  config.timeout = 60
end

# Usage
client = MyGem::Client.new
order = client.get_order(123)
```

### The Gemspec

```ruby
# my_gem.gemspec
Gem::Specification.new do |spec|
  spec.name          = "my_gem"
  spec.version       = MyGem::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["you@example.com"]
  spec.summary       = "A Ruby client for the Example API"
  spec.homepage      = "https://github.com/you/my_gem"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.0"

  # Dev dependencies in Gemfile, not gemspec (modern convention)
end
```

### Testing (Minitest)

```ruby
# test/test_helper.rb
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "my_gem"
require "minitest/autorun"
require "minitest/pride"
require "webmock/minitest"

# Configure for tests
MyGem.configure do |config|
  config.api_key = "test-key"
  config.base_url = "https://api.example.com"
end
```

```ruby
# test/my_gem/client_test.rb
require "test_helper"

class MyGem::ClientTest < Minitest::Test
  def setup
    @client = MyGem::Client.new
  end

  def test_get_order
    stub_request(:get, "https://api.example.com/orders/123")
      .to_return(status: 200, body: { id: 123, status: "pending" }.to_json, headers: { "Content-Type" => "application/json" })

    result = @client.get_order(123)

    assert_equal 123, result["id"]
    assert_equal "pending", result["status"]
  end

  def test_raises_on_auth_failure
    stub_request(:get, "https://api.example.com/orders/123")
      .to_return(status: 401)

    assert_raises MyGem::AuthenticationError do
      @client.get_order(123)
    end
  end

  def test_raises_on_rate_limit
    stub_request(:get, "https://api.example.com/orders/123")
      .to_return(status: 429)

    assert_raises MyGem::RateLimitError do
      @client.get_order(123)
    end
  end
end
```

## Why This Is Good

- **Convention over configuration.** `lib/my_gem.rb` → `require "my_gem"`. `lib/my_gem/client.rb` → `MyGem::Client`. The directory structure maps to the module structure.
- **Block configuration is idiomatic Ruby.** `MyGem.configure { |c| c.api_key = "..." }` is the pattern every Rubyist expects.
- **Custom error hierarchy.** `rescue MyGem::Error` catches all gem errors. `rescue MyGem::RateLimitError` catches specific ones. Clean, selective handling.
- **Dependency injection via constructor.** `Client.new(api_key: custom_key)` overrides config for testing. The default reads from global config for convenience.
- **Development dependencies in Gemfile.** Modern convention keeps dev deps out of the gemspec, keeping the gem lightweight for consumers.

## When To Apply

- **Every Ruby library, gem, or standalone project.** This structure scales from 3 files to 300.
- **CLI tools.** Add `exe/` or `bin/` directory with the executable script. Use `Thor` or `OptionParser` for argument parsing.
- **Internal company gems.** Same structure as public gems. Publish to a private gem server (Gemfury, GitHub Packages).

## When NOT To Apply

- **Rails apps.** Rails has its own conventions (`app/`, `config/`, `db/`). Don't fight them.
- **Single-file scripts.** A 50-line utility script doesn't need a gem structure. Just use `#!/usr/bin/env ruby` and run it.
