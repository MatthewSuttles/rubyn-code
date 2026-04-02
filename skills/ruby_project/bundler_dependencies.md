# Ruby: Bundler and Dependency Management

## Pattern

Use Bundler to manage dependencies. Pin versions carefully, group gems by environment, audit for vulnerabilities, and keep the Gemfile organized and commented.

### Gemfile Organization

```ruby
source "https://rubygems.org"
ruby "~> 3.3"

# ─── Core ───────────────────────────────────────────
gem "rails", "~> 8.0"
gem "pg", "~> 1.5"
gem "redis", "~> 5.0"
gem "puma", "~> 6.0"

# ─── Authentication & Authorization ─────────────────
gem "devise", "~> 4.9"
gem "pundit", "~> 2.3"

# ─── Background Jobs ────────────────────────────────
gem "sidekiq", "~> 7.2"
gem "sidekiq-cron", "~> 1.12"

# ─── API ─────────────────────────────────────────────
gem "grape", "~> 2.0"
gem "grape-entity", "~> 1.0"

# ─── External Services ──────────────────────────────
gem "faraday", "~> 2.9"
gem "anthropic", "~> 0.3"      # Claude API client
gem "stripe", "~> 10.0"

# ─── Frontend ────────────────────────────────────────
gem "turbo-rails", "~> 2.0"
gem "stimulus-rails", "~> 1.3"
gem "tailwindcss-rails", "~> 2.6"

group :development, :test do
  gem "debug"                   # Built-in Ruby debugger
  gem "dotenv-rails"            # Load .env in development
  gem "factory_bot_rails"       # Test factories
  gem "faker"                   # Generate fake data for seeds
end

group :development do
  gem "bullet"                  # N+1 query detection
  gem "rack-mini-profiler"      # Performance profiling
  gem "web-console"             # In-browser Rails console
  gem "rubocop-rails-omakase"   # Rails-recommended linting
  gem "annotate"                # Schema annotations on models
  gem "strong_migrations"       # Catch unsafe migrations
end

group :test do
  gem "capybara"                # System tests
  gem "selenium-webdriver"      # Browser driver
  gem "webmock"                 # Stub HTTP requests
  gem "simplecov", require: false  # Test coverage
  gem "mocha"                   # Mocking for Minitest
end

group :production do
  # Production-only gems (monitoring, APM)
end
```

### Version Constraints

```ruby
# Pessimistic operator (~>) — the RIGHT default
gem "rails", "~> 8.0"       # >= 8.0.0, < 9.0 (major updates require manual bump)
gem "pg", "~> 1.5"          # >= 1.5.0, < 2.0
gem "sidekiq", "~> 7.2"     # >= 7.2.0, < 8.0

# Exact pin — for gems where ANY update could break you
gem "anthropic", "0.3.2"    # Exactly this version

# No constraint — AVOID (accepts any version, including breaking changes)
gem "faraday"               # BAD: could jump from 2.x to 3.x on bundle update

# Greater than — rarely needed
gem "ruby", ">= 3.1"       # For gemspecs only, not Gemfiles
```

### Security Auditing

```bash
# Check for known vulnerabilities in your dependencies
gem install bundler-audit
bundle audit check --update

# Output:
# Name: actionpack
# Version: 7.0.4
# CVE: CVE-2023-22795
# Criticality: High
# Solution: upgrade to ~> 7.0.4.1

# Automate in CI
# .github/workflows/security.yml
# - run: bundle audit check --update
```

### Bundle Commands

```bash
# Install dependencies
bundle install

# Update a specific gem
bundle update sidekiq

# Update all gems within constraints
bundle update

# Show where a gem is installed
bundle show faraday

# Show dependency tree
bundle list

# Open a gem's source code in your editor
bundle open faraday

# Check for outdated gems
bundle outdated

# Verify Gemfile.lock matches Gemfile
bundle check
```

### Gemfile.lock — Always Commit It

```
# For APPLICATIONS (Rails apps, Sinatra apps):
# ✅ ALWAYS commit Gemfile.lock
# Ensures every developer and CI runs the exact same versions

# For GEMS (libraries you publish):
# ❌ Do NOT commit Gemfile.lock
# Add to .gitignore — consumers use their own lock file
# The gemspec defines version constraints, not exact versions
```

## Why This Is Good

- **Pessimistic version constraints prevent breaking changes.** `~> 8.0` allows patch and minor updates but blocks major version jumps that could break your app.
- **Groups keep production lean.** Development gems (bullet, rubocop) don't install on production servers.
- **Comments explain WHY a gem exists.** Future developers know what `anthropic` does without looking it up.
- **`bundle audit` catches CVEs.** Known vulnerabilities in dependencies are reported before they reach production.
- **Gemfile.lock ensures reproducibility.** Every environment runs the exact same gem versions.

## Anti-Pattern

```ruby
# BAD: No version constraints
gem "rails"
gem "pg"
gem "sidekiq"

# BAD: All gems in one ungrouped list
gem "rails"
gem "debug"       # Dev only — shouldn't install in production
gem "pg"
gem "capybara"    # Test only
gem "sidekiq"
gem "webmock"     # Test only

# BAD: Not committing Gemfile.lock
# .gitignore
Gemfile.lock      # DON'T DO THIS for applications
```

## When To Apply

- **Every Ruby project.** Bundler is non-negotiable. Use it from the first line of code.
- **Run `bundle audit` in CI.** Every build should check for vulnerabilities.
- **Update dependencies monthly.** `bundle outdated` → update one gem at a time → run tests → commit.
