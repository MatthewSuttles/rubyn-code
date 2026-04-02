# Code Quality: Null Object Pattern

## Pattern

Instead of returning `nil` and forcing callers to check for it, return a special Null Object that implements the same interface with safe, neutral behavior. Eliminates `nil` checks scattered throughout the codebase.

```ruby
# The real object
class User < ApplicationRecord
  def display_name = name.presence || email
  def plan_name = active_subscription&.plan || "free"
  def credit_balance = credit_ledger_entries.sum(:amount)
  def can_use_feature?(feature) = plan_features.include?(feature)
end

# The Null Object — same interface, safe defaults
class GuestUser
  def id = nil
  def display_name = "Guest"
  def email = nil
  def plan_name = "none"
  def credit_balance = 0
  def can_use_feature?(_feature) = false
  def admin? = false
  def persisted? = false
  def orders = Order.none  # Returns an empty ActiveRecord relation
  def projects = Project.none
end

# Controller — no nil checks anywhere
class ApplicationController < ActionController::Base
  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) || GuestUser.new
  end
end

# Views work without nil checks
<%= current_user.display_name %>  <!-- "Guest" for non-logged-in users -->
<% if current_user.can_use_feature?(:export) %>
  <%= link_to "Export", export_path %>
<% end %>

# Services work without nil checks
class Orders::ListService
  def call(user)
    user.orders.recent.page(1)  # GuestUser returns Order.none — empty relation
  end
end
```

Another example — missing configuration:

```ruby
# Instead of nil for missing config
class AppConfig
  def self.feature_flags
    @feature_flags ||= load_flags || NullFeatureFlags.new
  end
end

class NullFeatureFlags
  def enabled?(_flag) = false
  def percentage(_flag) = 0
  def variant(_flag) = "control"
  def to_h = {}
end

# Callers never check for nil
if AppConfig.feature_flags.enabled?(:new_dashboard)
  render_new_dashboard
end
```

Null Object for associations:

```ruby
class Order < ApplicationRecord
  belongs_to :discount, optional: true

  def effective_discount
    discount || NullDiscount.new
  end
end

class NullDiscount
  def code = "none"
  def percentage = 0
  def calculate(subtotal) = 0
  def active? = false
  def to_s = "No discount"
end

# No nil checks in calculation
class Orders::TotalCalculator
  def call(order)
    subtotal = order.line_items.sum(&:total)
    discount_amount = order.effective_discount.calculate(subtotal)
    subtotal - discount_amount
  end
end
```

## Why This Is Good

- **Eliminates nil checks.** No more `if current_user.present?`, `user&.name`, or `user.try(:email)`. Every method call is safe because the Null Object responds to everything.
- **Views are cleaner.** No `<% if current_user %>` guards wrapping every personalized element. The GuestUser provides sensible defaults.
- **Polymorphic behavior.** The code treats real users and guest users identically. The difference is in the object, not in every caller.
- **Prevents NoMethodError on nil.** The #1 runtime error in Ruby apps is calling a method on `nil`. Null Objects make this impossible for the wrapped concept.

## Anti-Pattern

Nil checks scattered throughout the codebase:

```ruby
# Controller
def show
  @order = current_user&.orders&.find_by(id: params[:id])
  redirect_to root_path unless @order
end

# View
<% if current_user %>
  Welcome, <%= current_user.name || "User" %>
  <% if current_user.active_subscription %>
    Plan: <%= current_user.active_subscription.plan %>
  <% else %>
    Plan: Free
  <% end %>
<% else %>
  Welcome, Guest
<% end %>

# Service
def calculate_discount(order)
  return 0 unless order.discount
  return 0 unless order.discount.active?
  order.discount.calculate(order.subtotal)
end
```

## Why This Is Bad

- **Nil checks multiply.** Every new feature that touches `current_user` needs its own nil guard. Across 50 views and 20 services, that's hundreds of `if present?` checks.
- **Forgetting one check causes a crash.** One missed `&.` or `if present?` and you get `NoMethodError: undefined method 'name' for nil:NilClass` in production.
- **Duplicated default logic.** `"Guest"` as a fallback appears in the view. `"Free"` as a default plan appears in both the view and a service. Change one, forget the others.

## When To Apply

- **Optional associations.** `belongs_to :discount, optional: true` → return a `NullDiscount` instead of nil.
- **Current user / authentication.** Non-logged-in users → `GuestUser` instead of nil.
- **Configuration that might not exist.** Missing feature flags, missing settings, missing integrations → Null Object with safe defaults.
- **Any method that currently returns nil and forces callers to check.** If 3+ callers check for nil from the same source, introduce a Null Object.

## When NOT To Apply

- **When nil is meaningful.** `User.find_by(email: email)` returning nil means "not found" — the caller needs to know this to show an error or create the user. A Null Object would hide the absence.
- **When the absence should be an error.** `Order.find(params[:id])` should raise `RecordNotFound`, not return a NullOrder. The request is invalid.
- **One or two nil checks.** If only one caller checks for nil, a simple `|| default` is clearer than a Null Object class.
- **Don't create Null Objects for every model.** Focus on the 2-3 concepts where nil checks are pervasive (current_user, optional associations used in calculations).

## Edge Cases

**Null Object with ActiveRecord::Relation behavior:**
Use `.none` to return an empty-but-chainable relation:

```ruby
class GuestUser
  def orders
    Order.none  # Returns an ActiveRecord relation that's always empty
    # .where, .count, .page all work — they just return 0/empty
  end
end

# This works: GuestUser.new.orders.recent.page(1).count => 0
```

**Testing with Null Objects:**

```ruby
RSpec.describe GuestUser do
  subject { described_class.new }

  it "responds to the same interface as User" do
    user_methods = %i[display_name email plan_name credit_balance can_use_feature? admin?]
    user_methods.each do |method|
      expect(subject).to respond_to(method)
    end
  end

  it "returns safe defaults" do
    expect(subject.display_name).to eq("Guest")
    expect(subject.credit_balance).to eq(0)
    expect(subject.can_use_feature?(:anything)).to be false
  end
end
```

**Combine with `#presence` for simple cases:**
For one-off nil handling, Ruby's `#presence` and `||` are sufficient:

```ruby
name = user.name.presence || "Anonymous"
```

Reserve the full Null Object pattern for when nil checks are pervasive.
