# Rails: Multitenancy

## Pattern

Multitenancy allows a single application instance to serve multiple organizations (tenants) with data isolation. Choose row-based tenancy (shared tables with a tenant_id column) for simplicity, or schema-based (separate PostgreSQL schemas per tenant) for stronger isolation.

### Row-Based Tenancy (Most Common)

```ruby
# Every tenanted model has an organization_id
class Order < ApplicationRecord
  belongs_to :organization
  belongs_to :user

  # Default scope is tempting but dangerous — use explicit scoping instead
end

class User < ApplicationRecord
  belongs_to :organization
  has_many :orders
end

# Set the current tenant per request
class ApplicationController < ActionController::Base
  before_action :set_current_organization

  private

  def set_current_organization
    Current.organization = current_user&.organization
  end
end

# Use Current attributes (Rails 5.2+) for request-scoped tenant
class Current < ActiveSupport::CurrentAttributes
  attribute :user, :organization
end
```

```ruby
# Scoping all queries to the current tenant
# Option A: Explicit scoping in controllers
class OrdersController < ApplicationController
  def index
    @orders = Current.organization.orders.recent
  end

  def show
    @order = Current.organization.orders.find(params[:id])
  end
end

# Option B: acts_as_tenant gem (automatic scoping)
# Gemfile: gem "acts_as_tenant"
class Order < ApplicationRecord
  acts_as_tenant :organization
  # Automatically adds: default_scope { where(organization_id: ActsAsTenant.current_tenant.id) }
  # Automatically validates: validates :organization_id, presence: true
  # Automatically sets: before_validation { self.organization_id = ActsAsTenant.current_tenant.id }
end

# Controller setup
class ApplicationController < ActionController::Base
  set_current_tenant_through_filter
  before_action :set_tenant

  private

  def set_tenant
    set_current_tenant(current_user.organization)
  end
end

# Now ALL queries are automatically scoped — no leaks possible
Order.all        # => WHERE organization_id = 42 (automatic)
Order.find(123)  # => WHERE id = 123 AND organization_id = 42 (automatic)
```

### Database Constraints for Safety

```ruby
# Migration — ensure tenant isolation at the database level
class AddOrganizationToOrders < ActiveRecord::Migration[8.0]
  def change
    add_reference :orders, :organization, null: false, foreign_key: true, index: true

    # Composite index for tenant-scoped queries
    add_index :orders, [:organization_id, :created_at]
    add_index :orders, [:organization_id, :status]

    # Unique constraints scoped to tenant
    add_index :orders, [:organization_id, :reference], unique: true
    # Order references are unique WITHIN an organization, not globally
  end
end
```

### Testing Multitenancy

```ruby
# RSpec
RSpec.describe Order, type: :model do
  let(:org_a) { create(:organization) }
  let(:org_b) { create(:organization) }

  around do |example|
    ActsAsTenant.with_tenant(org_a) { example.run }
  end

  it "scopes queries to the current tenant" do
    order_a = create(:order, organization: org_a)

    ActsAsTenant.with_tenant(org_b) do
      order_b = create(:order, organization: org_b)
      expect(Order.all).to eq([order_b])  # Only sees org_b's orders
      expect(Order.all).not_to include(order_a)
    end

    expect(Order.all).to eq([order_a])  # Back to org_a
  end
end

# Minitest
class OrderTest < ActiveSupport::TestCase
  setup do
    @org = organizations(:acme)
    ActsAsTenant.current_tenant = @org
  end

  teardown do
    ActsAsTenant.current_tenant = nil
  end

  test "orders are scoped to current tenant" do
    order = Order.create!(reference: "ORD-001", user: users(:alice))
    assert_equal @org, order.organization
  end
end
```

### Schema-Based Tenancy (Stronger Isolation)

```ruby
# Each tenant gets their own PostgreSQL schema
# Gem: apartment or acts_as_tenant with schema support

# With apartment gem (simpler):
# Gemfile: gem "ros-apartment", require: "apartment"

# config/initializers/apartment.rb
Apartment.configure do |config|
  config.excluded_models = %w[Organization User] # Shared tables
  config.tenant_names = -> { Organization.pluck(:subdomain) }
end

# Switching schemas
Apartment::Tenant.switch("acme") do
  # All queries hit the "acme" schema
  Order.all  # => SELECT * FROM acme.orders
end

# Request middleware sets tenant from subdomain
class ApplicationController < ActionController::Base
  before_action :set_tenant

  private

  def set_tenant
    subdomain = request.subdomain
    organization = Organization.find_by!(subdomain: subdomain)
    Apartment::Tenant.switch!(organization.subdomain)
  end
end
```

## Decision Matrix

| Factor | Row-Based | Schema-Based |
|---|---|---|
| Setup complexity | Low | Medium-High |
| Query performance | Good with indexes | Slightly better (smaller tables) |
| Data isolation | Application-enforced | Database-enforced |
| Cross-tenant queries | Easy (remove scope) | Hard (must switch schemas) |
| Tenant count | Unlimited | <1000 (each schema has overhead) |
| Migrations | Run once | Run per schema |
| Backups | One database | Per-schema or full DB |

**Recommendation:** Start with row-based + `acts_as_tenant`. It's simpler, handles 95% of use cases, and you can migrate to schema-based later if you need stronger isolation.

## When To Apply

- **SaaS applications** where multiple companies share one deployment.
- **Any app with an Organization/Account/Company model** that owns other data.
- **Rubyn itself** — the API server uses row-based tenancy with organization_id on projects, interactions, and credit_ledger.

## When NOT To Apply

- **Single-tenant apps.** If there's only one organization, skip the complexity.
- **B2C apps without organizations.** Users owning their own data is just `user_id` scoping, not multitenancy.
- **Don't add tenancy "just in case."** Add it when the second tenant appears, not before.

## Critical Safety Rules

1. **Never use `default_scope` for tenancy manually.** Use `acts_as_tenant` which handles it safely, or use explicit scoping. Hand-rolled default scopes are the #1 source of data leaks.
2. **Always scope `find` calls.** `Order.find(params[:id])` without tenant scoping lets any user access any order by guessing IDs.
3. **Background jobs must set the tenant.** Jobs run outside the request cycle. Pass `organization_id` to every job and set the tenant in `perform`.
4. **Console access defaults to no tenant.** `rails console` has no request context. Use `ActsAsTenant.with_tenant(org) { ... }` explicitly.
