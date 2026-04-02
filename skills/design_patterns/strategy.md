# Design Pattern: Strategy

## Pattern

Define a family of algorithms, put each in its own class, and make them interchangeable. The calling code (context) delegates to a strategy object and doesn't know or care which implementation it gets.

In Ruby, strategies can be classes, procs/lambdas, or any object that responds to the expected method — duck typing makes the pattern lightweight.

```ruby
# Strategy as classes — best for complex algorithms with their own state

class Credits::PricingStrategy
  def calculate_cost(input_tokens, output_tokens, cache_read_tokens)
    raise NotImplementedError
  end
end

class Credits::HaikuPricing < Credits::PricingStrategy
  INPUT_RATE = 1.0 / 1_000_000    # $1 per 1M input tokens
  OUTPUT_RATE = 5.0 / 1_000_000   # $5 per 1M output tokens
  CACHE_RATE = 0.1 / 1_000_000    # $0.10 per 1M cached tokens

  def calculate_cost(input_tokens, output_tokens, cache_read_tokens)
    (input_tokens * INPUT_RATE) +
      (output_tokens * OUTPUT_RATE) +
      (cache_read_tokens * CACHE_RATE)
  end
end

class Credits::SonnetPricing < Credits::PricingStrategy
  INPUT_RATE = 3.0 / 1_000_000
  OUTPUT_RATE = 15.0 / 1_000_000
  CACHE_RATE = 0.3 / 1_000_000

  def calculate_cost(input_tokens, output_tokens, cache_read_tokens)
    (input_tokens * INPUT_RATE) +
      (output_tokens * OUTPUT_RATE) +
      (cache_read_tokens * CACHE_RATE)
  end
end

# Context — doesn't know which pricing strategy it's using
class Credits::DeductionService
  def initialize(pricing: Credits::HaikuPricing.new)
    @pricing = pricing
  end

  def call(interaction)
    cost = @pricing.calculate_cost(
      interaction.input_tokens,
      interaction.output_tokens,
      interaction.cache_read_tokens
    )
    credits = (cost / Credits::COST_PER_CREDIT).ceil

    interaction.update!(credits_used: credits, cost_usd: cost)
    interaction.user.deduct_credits!(credits)
  end
end
```

Strategy as procs — best for simple, inline algorithms:

```ruby
class Orders::SortService
  STRATEGIES = {
    newest: ->(scope) { scope.order(created_at: :desc) },
    oldest: ->(scope) { scope.order(created_at: :asc) },
    highest: ->(scope) { scope.order(total: :desc) },
    alphabetical: ->(scope) { scope.joins(:user).order("users.name ASC") }
  }.freeze

  def call(orders, strategy_name:)
    strategy = STRATEGIES.fetch(strategy_name, STRATEGIES[:newest])
    strategy.call(orders)
  end
end
```

Strategy via Ruby blocks — maximum flexibility:

```ruby
class DataExporter
  def export(records, &formatter)
    records.map { |record| formatter.call(record) }.join("\n")
  end
end

exporter = DataExporter.new
exporter.export(orders) { |o| o.to_json }
exporter.export(orders) { |o| "#{o.reference},#{o.total}" }
```

## Why This Is Good

- **Adding a new algorithm doesn't touch existing code.** Adding `OpusPricing` means writing one new class. `DeductionService`, `HaikuPricing`, and `SonnetPricing` don't change.
- **Each strategy is independently testable.** Test `HaikuPricing#calculate_cost` with just numbers — no service, no user, no credits.
- **Runtime swappable.** Pro mode can use `SonnetPricing`, free tier uses `HaikuPricing`, all determined at runtime without conditionals in the service.
- **Ruby's duck typing makes it lightweight.** No interfaces to declare, no abstract classes to inherit from. Any object with `calculate_cost(input, output, cache)` is a valid strategy.

## When To Apply

- You have **multiple algorithms for the same task** — pricing models, sorting methods, formatting options, authentication strategies.
- The algorithm **varies at runtime** based on user input, configuration, or feature flags.
- You find yourself writing `case/when` or `if/elsif` chains that select different behavior based on a type.
- You want to **test algorithms in isolation** without the context that uses them.

## When NOT To Apply

- **Two simple branches that won't grow.** An `if premium?` / `else` is clearer than a strategy pattern for two options that are unlikely to become three.
- **The "algorithm" is a single line.** `collection.sort_by(&:name)` vs `collection.sort_by(&:created_at)` doesn't need a strategy class — just pass the sort key.
- **The behavior never varies at runtime.** If the app always uses Haiku pricing and will never use anything else, injecting a strategy adds unnecessary indirection.

## Rails Example

```ruby
# config/initializers/pricing.rb
PRICING_STRATEGIES = {
  "haiku" => Credits::HaikuPricing.new,
  "sonnet" => Credits::SonnetPricing.new,
  "opus" => Credits::OpusPricing.new
}.freeze

# Used in the interaction pipeline
pricing = PRICING_STRATEGIES.fetch(interaction.model_tier, PRICING_STRATEGIES["haiku"])
Credits::DeductionService.new(pricing: pricing).call(interaction)
```
