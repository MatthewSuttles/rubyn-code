# Gems: RuboCop

## Pattern

RuboCop enforces consistent Ruby style across the team. Start with a reasonable base configuration, customize to match your project's conventions, and run it in CI to catch violations before code review.

### Setup

```ruby
# Gemfile
group :development, :test do
  gem "rubocop", require: false
  gem "rubocop-rails", require: false          # Rails-specific cops
  gem "rubocop-rspec", require: false          # RSpec-specific cops (if using RSpec)
  gem "rubocop-minitest", require: false       # Minitest-specific cops (if using Minitest)
  gem "rubocop-performance", require: false    # Performance-focused cops
  gem "rubocop-rails-omakase", require: false  # DHH's Rails opinions (optional)
end
```

### Configuration

```yaml
# .rubocop.yml
require:
  - rubocop-rails
  - rubocop-rspec        # or rubocop-minitest
  - rubocop-performance

AllCops:
  TargetRubyVersion: 3.3
  NewCops: enable
  Exclude:
    - "db/schema.rb"
    - "db/migrate/**/*"
    - "bin/**/*"
    - "vendor/**/*"
    - "node_modules/**/*"
    - "tmp/**/*"

# ─── Style ──────────────────────────────────────
Style/FrozenStringLiteralComment:
  Enabled: true
  EnforcedStyle: always

Style/StringLiterals:
  EnforcedStyle: double_quotes

Style/SymbolArray:
  EnforcedStyle: brackets

Style/WordArray:
  EnforcedStyle: brackets

Style/Documentation:
  Enabled: false  # Don't require class documentation comments

Style/ClassAndModuleChildren:
  Enabled: false  # Allow both nested and compact styles

# ─── Layout ─────────────────────────────────────
Layout/LineLength:
  Max: 120                    # 80 is too aggressive for modern screens
  AllowedPatterns:
    - "^\\s*#"                # Don't enforce on comments
    - "https?://"             # Don't break URLs

Layout/MultilineMethodCallIndentation:
  EnforcedStyle: indented

# ─── Metrics ────────────────────────────────────
Metrics/MethodLength:
  Max: 15                     # Default 10 is too strict for real-world Rails
  CountAsOne:
    - array
    - hash
    - heredoc
  Exclude:
    - "db/migrate/**/*"

Metrics/ClassLength:
  Max: 200                    # Models can be long — extract when it hurts
  Exclude:
    - "app/models/**/*"       # Models get a pass — concerns handle extraction

Metrics/AbcSize:
  Max: 20                     # Default 17 triggers on straightforward methods

Metrics/BlockLength:
  Exclude:
    - "spec/**/*"             # RSpec blocks are naturally long
    - "test/**/*"             # Minitest blocks too
    - "config/routes.rb"
    - "config/environments/**/*"
    - "lib/tasks/**/*"
    - "*.gemspec"

# ─── Rails ──────────────────────────────────────
Rails/HasManyOrHasOneDependent:
  Enabled: true               # Force dependent: option on has_many/has_one

Rails/InverseOf:
  Enabled: true               # Suggest inverse_of on associations

Rails/UnknownEnv:
  Environments:
    - production
    - development
    - test
    - staging

# ─── RSpec ──────────────────────────────────────
RSpec/ExampleLength:
  Max: 15                     # Default 5 is too strict
  CountAsOne:
    - array
    - hash
    - heredoc

RSpec/MultipleExpectations:
  Max: 5                      # Allow aggregate_failures style

RSpec/NestedGroups:
  Max: 4

RSpec/MultipleMemoizedHelpers:
  Max: 8                      # Real specs need setup

# ─── Performance ────────────────────────────────
Performance/CollectionLiteralInLoop:
  Enabled: true

Performance/Count:
  Enabled: true               # Prefer .count over .select { }.size

Performance/Detect:
  Enabled: true               # Prefer .detect over .select { }.first
```

### Running

```bash
# Check all files
bundle exec rubocop

# Check specific files
bundle exec rubocop app/models/order.rb

# Auto-correct safe violations
bundle exec rubocop -a

# Auto-correct all violations (including unsafe)
bundle exec rubocop -A

# Generate a TODO file for existing violations (adopt incrementally)
bundle exec rubocop --auto-gen-config
# Creates .rubocop_todo.yml — inherit from it and fix violations over time

# Check only new/modified files (CI optimization)
bundle exec rubocop --only-changed
```

### CI Integration

```yaml
# .github/workflows/lint.yml
name: Lint
on: [push, pull_request]
jobs:
  rubocop:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bundle exec rubocop --parallel
```

### Incremental Adoption for Existing Projects

```bash
# Step 1: Generate TODO file listing all current violations
bundle exec rubocop --auto-gen-config --auto-gen-only-exclude

# Step 2: Add to .rubocop.yml
# inherit_from: .rubocop_todo.yml

# Step 3: Fix violations gradually
# Each PR that touches a file fixes its violations
# Over time, the TODO file shrinks to zero

# Step 4: Remove the TODO file when it's empty
```

### Custom Cops (Advanced)

```ruby
# lib/rubocop/cop/custom/no_direct_api_calls.rb
module RuboCop
  module Cop
    module Custom
      class NoDirectApiCalls < Base
        MSG = "Use a service object or adapter instead of calling external APIs directly in controllers."

        RESTRICTED_RECEIVERS = %w[Faraday Net::HTTP HTTParty RestClient].freeze

        def on_send(node)
          return unless in_controller?(node)
          return unless RESTRICTED_RECEIVERS.include?(node.receiver&.const_name)

          add_offense(node)
        end

        private

        def in_controller?(node)
          node.each_ancestor(:class).any? do |klass|
            klass.identifier.source.end_with?("Controller")
          end
        end
      end
    end
  end
end
```

```yaml
# .rubocop.yml
require:
  - ./lib/rubocop/cop/custom/no_direct_api_calls

Custom/NoDirectApiCalls:
  Enabled: true
  Include:
    - "app/controllers/**/*"
```

## Why This Is Good

- **Consistent style without arguments.** The config decides once. Every developer and every PR follows the same style. No more "tabs vs spaces" debates.
- **Catches real bugs.** `Rails/HasManyOrHasOneDependent` catches missing `dependent:` options. `Performance/Detect` catches `.select { }.first` instead of `.detect`. These are functional improvements, not just style.
- **Auto-correct saves time.** `rubocop -a` fixes 70-80% of violations automatically. String quote style, trailing whitespace, frozen string literal — all fixed in one command.
- **Incremental adoption.** `--auto-gen-config` lets you adopt RuboCop on existing projects without fixing 500 violations in one PR. Fix as you go.
- **CI enforcement.** Violations are caught before code review. Reviewers focus on design and logic, not style.

## When To Apply

- **Every Ruby project.** RuboCop is non-negotiable. Install it, configure it, run it in CI.
- **Day one of a new project.** Start clean — no TODO file needed.
- **Existing projects.** Use `--auto-gen-config` for gradual adoption. Fix violations file-by-file as you touch them.

## When NOT To Apply

- **Don't enforce every cop.** Disable cops that don't match your team's preferences. `Style/Documentation` (requires class comments) is commonly disabled. `Metrics/MethodLength: 10` is too strict for most Rails apps.
- **Don't auto-correct in bulk on large codebases.** A 500-file auto-correct commit is impossible to review. Fix incrementally.
- **Don't write custom cops until you have 50+ files.** Standard cops cover 99% of needs. Custom cops are for team-specific architectural rules.
