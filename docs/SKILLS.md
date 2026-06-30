# Skills Authoring Guide

## What Are Skills?

Skills are curated markdown documents that inject domain-specific knowledge into the
LLM's context on demand. Rubyn Code ships with 112 built-in skills covering Ruby,
Rails, RSpec, design patterns, refactoring, and more. Skills are organized by
category in the `skills/` directory.

When a skill is loaded, its content is wrapped in `<skill>` XML tags and injected
into the conversation context. This gives the LLM focused, high-quality reference
material for the current task without permanently consuming context window space
(skills are automatically ejected after a period of inactivity).

Skills can be loaded in two ways:
- **By the user:** via the `/skill` slash command or by asking the agent to load one
- **By the agent:** via the `load_skill` tool when it detects a relevant skill

---

## Frontmatter Format

Skills use YAML frontmatter to declare metadata. The frontmatter is delimited by
`---` markers at the top of the file:

```markdown
---
name: factory-bot
description: FactoryBot patterns for test data generation in RSpec
tags: [rspec, testing, factories]
---

# FactoryBot Best Practices

Your skill content goes here...
```

### Frontmatter Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | String | No | Skill identifier used for loading (e.g. `factory-bot`). Derived from filename if omitted. |
| `description` | String | No | One-line summary shown in skill listings. Derived from first heading if omitted. |
| `tags` | Array | No | Keywords for categorization and auto-detection. Used by tag-matching rules. |

### Without Frontmatter

Skills work without frontmatter. If the `---` delimiters are absent:

- **Name** is derived from the filename: `blocks_procs_lambdas.md` becomes
  `blocks-procs-lambdas`
- **Description** is extracted from the first heading (`# Title`) or first line
- **Tags** are auto-derived by matching the name and body against keyword rules
  (ruby, rails, rspec, testing, patterns, refactoring)

Example without frontmatter:

```markdown
# Ruby: Blocks, Procs, and Lambdas

## Pattern

Blocks are Ruby's most powerful feature...
```

This auto-discovers as name `blocks-procs-lambdas` with tags `[ruby]`.

---

## How Skills Are Discovered and Indexed

The `Skills::Catalog` class handles discovery:

1. **Directory scanning:** Catalogs all `.md` files recursively under configured
   skills directories using the glob pattern `**/*.md`.

2. **Configured directories:** By default, two directories are scanned:
   - The gem's built-in `skills/` directory (112 curated skills)
   - Project-level `.rubyn-code/skills/` directory (if it exists)

3. **Index building:** For each `.md` file found, the catalog reads the first 1024
   bytes, parses the frontmatter (or derives metadata), and stores an entry with
   `name`, `description`, and `path`.

4. **Deduplication:** If two skills have the same name, the first one found wins.
   Project-level skills can shadow built-in skills by using the same name.

5. **Prompt injection:** At session start, the agent receives a listing of all
   available skills (name + description) so it knows what it can load.

---

## TTL Behavior

Skills loaded into context are managed by `Skills::TtlManager` to prevent context
bloat:

### Turn-Based Expiry

Each loaded skill has a TTL (time-to-live) measured in conversation turns. The
default TTL is **5 turns**. Every time the agent loop processes a user message,
the turn counter advances.

### Reference Tracking

When a skill is referenced (the agent uses knowledge from it or the user asks about
the topic), the skill's TTL countdown resets. A skill that is actively being used
will not expire.

### Automatic Ejection

Skills that exceed their TTL without being referenced are marked as expired. During
the next compaction pass, expired skills are ejected from context, freeing tokens
for new content.

### Size Caps

Skills are capped at **800 tokens** (~3200 characters). Longer skills are truncated
with a `[skill truncated to 800 tokens]` marker. This prevents a single large skill
from consuming too much context.

### TTL Stats

The TTL manager tracks:
- Number of currently loaded skills
- Total tokens used by loaded skills
- Number of expired (pending ejection) skills
- Current turn counter

---

## Creating Project-Specific Skills

Project skills live in the `.rubyn-code/skills/` directory within your project root.
They are discovered automatically alongside the built-in skills.

### Step-by-Step

1. Create the directory:
   ```bash
   mkdir -p .rubyn-code/skills
   ```

2. Create a skill file:
   ```bash
   touch .rubyn-code/skills/our-api-patterns.md
   ```

3. Write the skill with frontmatter:
   ```markdown
   ---
   name: our-api-patterns
   description: API design patterns and conventions for this project
   tags: [api, patterns, conventions]
   ---

   # API Design Patterns

   ## Authentication
   All API endpoints use Bearer token authentication via the
   `Authenticatable` concern...

   ## Response Format
   Always return JSON:API compliant responses...

   ## Versioning
   API versions are namespaced under `/api/v{n}/`...
   ```

4. The skill is immediately available. Load it with:
   ```
   /skill our-api-patterns
   ```
   Or ask the agent: "Load the our-api-patterns skill."

### Project Skill Ideas

- **Coding conventions:** Style rules, naming patterns, architectural decisions
- **Domain knowledge:** Business rules, entity relationships, workflow descriptions
- **Setup guides:** How to run the app, seed data, configure dependencies
- **API documentation:** Endpoint contracts, authentication, error codes
- **Testing patterns:** Project-specific test helpers, factory patterns, fixtures

---

## Creating Global Skills

Global skills live in `~/.rubyn-code/skills/` and are available across all projects.

```bash
mkdir -p ~/.rubyn-code/skills
```

Create skills the same way as project skills. Global skills are useful for:

- Personal coding style preferences
- Language idioms you reference frequently
- Framework patterns you use across multiple projects

---

## Skill Selection Logic

The agent decides which skills to suggest or auto-load based on several signals:

### Manual Loading

The user or agent can explicitly load a skill by name using the `/skill` command or
the `load_skill` tool. This always works regardless of matching logic.

### Skill Listing in System Prompt

At session start, `Skills::Loader#descriptions_for_prompt` generates a listing of
all available skills (name + description) that is injected into the system prompt.
The LLM can then decide to load relevant skills based on the conversation context.

### Name-Based Discovery

`Skills::Catalog#find(name)` looks up a skill by exact name match. The name is
either from the frontmatter `name` field or derived from the filename.

### Tag-Based Auto-Detection

`Skills::Document` auto-derives tags from content using keyword rules:
- `ruby` -- matches `/\bruby\b/i`
- `rails` -- matches `/\brails\b/i`
- `rspec` -- matches `/\brspec\b/i`
- `testing` -- matches `/\b(?:test|spec|minitest)\b/i`
- `patterns` -- matches `/\b(?:pattern|design|solid)\b/i`
- `refactoring` -- matches `/\brefactor/i`

---

## Best Practices for Writing Effective Skills

### 1. Keep Skills Focused

Each skill should cover one specific topic. A skill about "ActiveRecord Querying"
is better than a skill about "All of ActiveRecord." Focused skills load faster
and are ejected cleanly when no longer needed.

### 2. Lead with Patterns, Not Encyclopedias

Start with the most common patterns and best practices. The LLM already knows the
basics -- your skill should provide the opinionated guidance for *how* to use
something well.

```markdown
# Good: Pattern-focused
## Pattern
Use `find_by` over `where.first`, `exists?` over loading records to check
presence, and `pluck` when you only need column values.

# Bad: Encyclopedia-style
## What is ActiveRecord?
ActiveRecord is an ORM that maps database tables to Ruby classes...
```

### 3. Include Code Examples

Concrete code examples are the most valuable part of a skill. Show the recommended
pattern with real-world code:

```markdown
## Factory Design

```ruby
# Good: minimal factories with traits
factory :user do
  email { Faker::Internet.email }
  name { Faker::Name.name }

  trait :admin do
    role { :admin }
  end

  trait :with_posts do
    after(:create) do |user|
      create_list(:post, 3, author: user)
    end
  end
end
```
```

### 4. Stay Within the Size Cap

Skills are truncated at ~3200 characters (800 tokens). Keep your skills concise.
If you need to cover a large topic, split it into multiple skills:

```
.rubyn-code/skills/
  auth-jwt.md          # JWT authentication patterns
  auth-oauth.md        # OAuth integration patterns
  auth-permissions.md  # Authorization/permissions
```

### 5. Use Descriptive Frontmatter

Good frontmatter helps the agent decide when to suggest your skill:

```yaml
---
name: sidekiq-patterns
description: Sidekiq job design patterns, error handling, and performance tips
tags: [sidekiq, background-jobs, performance]
---
```

### 6. Organize by Category

For project skills, use subdirectories to organize by category:

```
.rubyn-code/skills/
  api/
    authentication.md
    pagination.md
    error-handling.md
  domain/
    order-lifecycle.md
    payment-processing.md
  testing/
    integration-test-patterns.md
    factory-conventions.md
```

### 7. Include Anti-Patterns

Showing what NOT to do is as valuable as showing what to do:

```markdown
## Anti-Pattern: N+1 Queries

```ruby
# Bad: N+1 query
users.each { |u| puts u.posts.count }

# Good: eager load
users.includes(:posts).each { |u| puts u.posts.size }
```
```

### 8. Reference Project Conventions

For project-specific skills, reference actual files, class names, and patterns from
your codebase:

```markdown
## Service Object Pattern

All service objects inherit from `ApplicationService` (see
`app/services/application_service.rb`) and implement a `.call` class method:

```ruby
class ProcessPayment < ApplicationService
  def initialize(order:, payment_method:)
    @order = order
    @payment_method = payment_method
  end

  def call
    # implementation
  end
end
```
```

---

## Built-in Skill Categories

Rubyn Code ships with 112 skills organized into these categories:

| Directory | Topics |
|-----------|--------|
| `skills/ruby/` | Core Ruby: blocks, classes, concurrency, data structures, debugging, enumerables, exceptions, file I/O, hashes, metaprogramming, etc. |
| `skills/rails/` | Rails: ActionCable, ActiveRecord, controllers, migrations, routing, testing, Turbo, etc. |
| `skills/rspec/` | RSpec: factories, mocking, shared examples, request/system specs, performance, etc. |
| `skills/design_patterns/` | Design patterns: adapter, builder, decorator, observer, strategy, etc. |
| `skills/refactoring/` | Refactoring techniques and code smell detection |
| `skills/gems/` | Popular gem usage patterns |
| `skills/code_quality/` | Code quality, linting, static analysis |
| `skills/minitest/` | Minitest patterns and practices |
| `skills/sinatra/` | Sinatra application patterns |
| `skills/solid/` | SOLID principles applied to Ruby |
| `skills/ruby_project/` | Ruby project setup and tooling |
