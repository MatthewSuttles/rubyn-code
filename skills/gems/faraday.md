# Gem: Faraday

## What It Is

Faraday is the standard Ruby HTTP client library. It provides a consistent interface for making HTTP requests with middleware for logging, retries, JSON parsing, authentication, and error handling. It's adapter-agnostic — you can swap the backend (Net::HTTP, Typhoeus, Patron) without changing your code.

## Setup Done Right

```ruby
# Build a reusable client with middleware
class AnthropicClient
  BASE_URL = "https://api.anthropic.com".freeze

  def initialize(api_key: ENV.fetch("ANTHROPIC_API_KEY"))
    @conn = Faraday.new(url: BASE_URL) do |f|
      f.request :json                          # Encode request body as JSON
      f.response :json                         # Parse response body as JSON
      f.response :raise_error                  # Raise on 4xx/5xx responses
      f.request :retry, {                      # Retry on transient failures
        max: 3,
        interval: 0.5,
        interval_randomness: 0.5,
        backoff_factor: 2,
        retry_statuses: [429, 500, 502, 503],
        methods: %i[get post],
        retry_block: ->(env, opts, retries, exc) {
          Rails.logger.warn("[Anthropic] Retry #{retries}: #{exc&.message}")
        }
      }
      f.request :authorization, "x-api-key", api_key
      f.headers["anthropic-version"] = "2023-06-01"
      f.options.timeout = 60                   # Read timeout
      f.options.open_timeout = 10              # Connection timeout
      f.adapter Faraday.default_adapter
    end
  end

  def complete(messages, model:, max_tokens:, system: nil)
    body = {
      model: model,
      max_tokens: max_tokens,
      messages: messages
    }
    body[:system] = system if system

    response = @conn.post("/v1/messages", body)
    response.body
  end
end
```

## Gotcha #1: Middleware Order Matters

Faraday middleware runs in the order declared for requests (top to bottom) and reverse order for responses (bottom to top). Getting this wrong causes subtle bugs.

```ruby
# WRONG: response :json is before response :raise_error
Faraday.new(url: BASE_URL) do |f|
  f.request :json
  f.response :json          # Parses response FIRST
  f.response :raise_error   # Then checks status — but the body is already parsed
  # If the API returns 500 with non-JSON body, :json middleware chokes
end

# RIGHT: raise_error runs before json parsing (remember: response middleware is reversed)
Faraday.new(url: BASE_URL) do |f|
  f.request :json           # Encode request as JSON
  f.response :raise_error   # Check status FIRST (this actually runs AFTER :json response)
  f.response :json          # Then parse response body
  # Wait — this is also wrong! Let me explain...
end

# ACTUALLY RIGHT: In Faraday, response middleware executes in REVERSE order
# So if you want raise_error to run AFTER json parsing:
Faraday.new(url: BASE_URL) do |f|
  f.request :json
  f.response :json           # Parses body first (runs second in reverse order)
  f.response :raise_error    # Then raises if status is bad (runs first in reverse order)
  # No wait — raise_error runs BEFORE json in reverse order
end

# THE ACTUAL CORRECT ORDER:
Faraday.new(url: BASE_URL) do |f|
  f.request :json
  f.response :raise_error    # Declared first = runs LAST for responses
  f.response :json           # Declared second = runs FIRST for responses
  # So: response arrives → json parses it → raise_error checks status
  # If response is 500, raise_error sees parsed body and raises with details
end
```

**The trap:** The mental model is confusing because request middleware runs top-to-bottom but response middleware runs bottom-to-top. When in doubt, test with a failing request and check which error you get.

Simplest rule: **put `:raise_error` ABOVE `:json`** in the middleware stack.

## Gotcha #2: Timeouts — Set Them or Hang Forever

Default Faraday has no timeout. A hung server means your Ruby process hangs forever, tying up a web worker or Sidekiq thread.

```ruby
# WRONG: No timeouts — will hang indefinitely
conn = Faraday.new(url: "https://slow-api.example.com")
response = conn.get("/data")  # Waits forever if server doesn't respond

# RIGHT: Always set timeouts
conn = Faraday.new(url: "https://api.example.com") do |f|
  f.options.timeout = 30         # Total read timeout (seconds)
  f.options.open_timeout = 5     # Connection timeout (seconds)
  f.options.write_timeout = 10   # Write timeout (seconds) — Ruby 2.6+
end

# Per-request timeout override
response = conn.get("/data") do |req|
  req.options.timeout = 5  # This specific request times out faster
end
```

**The trap:** Your app works fine for weeks. Then the external API has a slowdown. Without timeouts, your web workers all hang waiting for responses, your request queue fills up, and your entire app goes down — not just the feature that calls the API.

## Gotcha #3: The `raise_error` Middleware

Without `raise_error`, Faraday returns the response object even on 4xx/5xx — it does NOT raise an exception.

```ruby
# WRONG: Assuming Faraday raises on errors
conn = Faraday.new(url: "https://api.example.com")
response = conn.get("/missing-resource")
# response.status is 404, but NO exception raised
# The code continues with a 404 response and breaks later

data = response.body["results"]  # nil — body is an error page, not JSON
data.each { |r| process(r) }     # NoMethodError: undefined method 'each' for nil

# RIGHT: Use raise_error middleware
conn = Faraday.new(url: "https://api.example.com") do |f|
  f.response :raise_error
end

begin
  response = conn.get("/missing-resource")
rescue Faraday::ResourceNotFound => e
  Rails.logger.warn("Resource not found: #{e.message}")
  nil
rescue Faraday::ClientError => e      # 4xx errors
  Rails.logger.error("Client error: #{e.message}")
  raise
rescue Faraday::ServerError => e      # 5xx errors
  Rails.logger.error("Server error: #{e.message}")
  raise
end
```

**Error class hierarchy:**
```
Faraday::Error
├── Faraday::ConnectionFailed     # Network unreachable, DNS failure
├── Faraday::TimeoutError         # Read/open timeout
├── Faraday::ClientError          # 4xx responses
│   ├── Faraday::BadRequestError          # 400
│   ├── Faraday::UnauthorizedError        # 401
│   ├── Faraday::ForbiddenError           # 403
│   ├── Faraday::ResourceNotFound         # 404
│   ├── Faraday::ProxyAuthError           # 407
│   ├── Faraday::ConflictError            # 409
│   ├── Faraday::UnprocessableEntityError # 422
│   └── Faraday::TooManyRequestsError    # 429
└── Faraday::ServerError          # 5xx responses
```

## Gotcha #4: Retry Middleware Configuration

The retry middleware only retries idempotent methods (GET, HEAD, OPTIONS) by default. POST requests are NOT retried unless you configure it.

```ruby
# WRONG: retry only works on GET by default
Faraday.new do |f|
  f.request :retry, max: 3
  # POST /v1/messages will NOT be retried on timeout
end

# RIGHT: Explicitly include POST if your API is idempotent
Faraday.new do |f|
  f.request :retry, {
    max: 3,
    methods: %i[get post],          # Include POST
    retry_statuses: [429, 500, 502, 503],
    exceptions: [
      Faraday::TimeoutError,
      Faraday::ConnectionFailed,
      Faraday::RetriableResponse    # Required for retry_statuses to work
    ]
  }
end
```

**The trap:** You add retry middleware for your AI API calls. GET requests retry fine, but POST requests to Claude never retry on 429 (rate limit). You need `methods: %i[get post]` AND `Faraday::RetriableResponse` in the exceptions list for status-based retries to work.

## Gotcha #5: JSON Parsing Failures

The `:json` response middleware silently returns the raw string body if JSON parsing fails. Your code expects a Hash but gets a String.

```ruby
# API returns HTML error page instead of JSON
response = conn.get("/api/data")
response.body  # "<html><body>502 Bad Gateway</body></html>" — not a Hash!
response.body["data"]  # Returns "a" (String#[] with string key)... not nil!

# RIGHT: Check response content type or rescue parse errors
response = conn.get("/api/data")
unless response.headers["content-type"]&.include?("application/json")
  raise "Unexpected response format: #{response.headers['content-type']}"
end
```

## Gotcha #6: Streaming Responses

For AI APIs that stream responses (SSE), you need to handle the response body differently.

```ruby
# Streaming with Faraday
def stream_completion(messages, &block)
  @conn.post("/v1/messages") do |req|
    req.body = {
      model: "claude-haiku-4-5-20251001",
      max_tokens: 4096,
      messages: messages,
      stream: true
    }.to_json
    req.options.on_data = proc do |chunk, overall_received_bytes, env|
      # chunk is a raw string, possibly multiple SSE events
      chunk.each_line do |line|
        next unless line.start_with?("data: ")
        data = line.sub("data: ", "").strip
        next if data == "[DONE]"
        block.call(JSON.parse(data))
      end
    end
  end
end

# Usage
stream_completion(messages) do |event|
  print event.dig("delta", "text")
end
```

## Do's and Don'ts Summary

**DO:**
- Always set `timeout` and `open_timeout` on every connection
- Use `raise_error` middleware so HTTP errors become Ruby exceptions
- Configure retry middleware explicitly — include POST methods if API is idempotent
- Wrap Faraday connections in client classes (Adapter pattern)
- Log requests and responses in development
- Rescue specific Faraday error classes, not generic `StandardError`

**DON'T:**
- Don't use Faraday without timeouts — one hung request can take down your app
- Don't assume response body is JSON — check content type or handle parse failures
- Don't forget `Faraday::RetriableResponse` in retry exceptions when using `retry_statuses`
- Don't create a new Faraday connection per request — reuse connections
- Don't put API keys directly in connection setup — use ENV or Rails credentials
- Don't ignore middleware order — it's the #1 source of confusing bugs
