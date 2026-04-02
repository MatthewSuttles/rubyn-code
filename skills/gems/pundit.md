# Gem: Pundit

## What It Is

Pundit provides authorization through plain Ruby policy classes. Each model gets a policy class that defines who can do what. It's intentionally simple — no DSL, no roles table, no configuration. Just Ruby classes with methods that return true/false.

## Setup Done Right

```ruby
# Gemfile
gem 'pundit'

# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  include Pundit::Authorization

  # CRITICAL: Ensure every action is authorized
  after_action :verify_authorized, except: :index
  after_action :verify_policy_scoped, only: :index

  # Handle unauthorized access gracefully
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  private

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back(fallback_location: root_path)
  end
end
```

```ruby
# app/policies/application_policy.rb
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  # Default: deny everything. Policies opt IN to permissions.
  def index? = false
  def show? = false
  def create? = false
  def new? = create?
  def update? = false
  def edit? = update?
  def destroy? = false

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "#{self.class} must implement #resolve"
    end

    private

    attr_reader :user, :scope
  end
end
```

```ruby
# app/policies/order_policy.rb
class OrderPolicy < ApplicationPolicy
  def show?
    owner? || admin?
  end

  def create?
    user.present? && user.credit_balance > 0
  end

  def update?
    owner? && record.editable?
  end

  def destroy?
    owner? && record.pending?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(user: user)
      end
    end
  end

  private

  def owner?
    record.user == user
  end

  def admin?
    user&.admin?
  end
end
```

```ruby
# Controller usage
class OrdersController < ApplicationController
  def index
    @orders = policy_scope(Order).recent.page(params[:page])
  end

  def show
    @order = Order.find(params[:id])
    authorize @order
  end

  def create
    @order = current_user.orders.build(order_params)
    authorize @order

    if @order.save
      redirect_to @order
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @order = Order.find(params[:id])
    authorize @order

    if @order.update(order_params)
      redirect_to @order
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @order = Order.find(params[:id])
    authorize @order
    @order.destroy
    redirect_to orders_path
  end
end
```

## Gotcha #1: Forgetting to Authorize

The #1 Pundit bug: you add a new action and forget to call `authorize`. Without `verify_authorized`, the action silently works for everyone — including users who shouldn't have access.

```ruby
# WRONG: No authorization — anyone can export
def export
  @orders = Order.all  # SECURITY HOLE: No policy check
  send_data generate_csv(@orders)
end

# RIGHT: Authorize explicitly
def export
  @orders = policy_scope(Order)
  authorize Order, :export?  # Checks OrderPolicy#export?
  send_data generate_csv(@orders)
end
```

**The trap:** `verify_authorized` in `after_action` catches this in development — you'll get `Pundit::AuthorizationNotPerformedError`. But only if you set it up. Without the `after_action`, forgotten authorization is a silent security hole.

**Skipping verification for specific actions:**

```ruby
# When an action legitimately doesn't need authorization
def health_check
  skip_authorization  # Explicitly marks this action as not needing auth
  render json: { status: "ok" }
end

def index
  @orders = policy_scope(Order)  # policy_scope satisfies verify_policy_scoped
  # No need for authorize — verify_policy_scoped is separate from verify_authorized
end
```

## Gotcha #2: `authorize` Must Be Called on the Right Object

```ruby
# WRONG: Authorizing the class when you should authorize the instance
def update
  @order = Order.find(params[:id])
  authorize Order  # Checks if user can update ANY order, not THIS order
  # OrderPolicy#update? receives the Order CLASS, not the instance
  # record.user == user will fail because Class doesn't have .user
end

# RIGHT: Authorize the specific record
def update
  @order = Order.find(params[:id])
  authorize @order  # Checks if user can update THIS specific order
end

# RIGHT: Authorize the class for collection actions
def create
  @order = current_user.orders.build(order_params)
  authorize @order  # Instance is fine here — Pundit infers the policy
end

# RIGHT: Authorize with explicit policy action
def publish
  @order = Order.find(params[:id])
  authorize @order, :publish?  # Calls OrderPolicy#publish?, not #update?
end
```

**The trap:** The action name maps to the policy method automatically (`create` action → `create?` policy method). If your action has a non-standard name (like `publish`, `export`, `approve`), you MUST pass the policy method explicitly: `authorize @order, :publish?`.

## Gotcha #3: Policy Scope vs Authorize

They're different things for different purposes:

```ruby
# policy_scope: Filters a COLLECTION. Returns only records the user can see.
# Used in index actions. Satisfies verify_policy_scoped.
def index
  @orders = policy_scope(Order)  # Calls OrderPolicy::Scope#resolve
end

# authorize: Checks permission on a SINGLE record. Returns the record or raises.
# Used in show/create/update/destroy. Satisfies verify_authorized.
def show
  @order = Order.find(params[:id])
  authorize @order  # Calls OrderPolicy#show?
end
```

**The trap:** Using `authorize` in an index action doesn't filter records — it just checks if the user can access the index page. You still need `policy_scope` to filter WHICH records they see.

```ruby
# WRONG: Authorizes index access but shows ALL orders to everyone
def index
  authorize Order, :index?
  @orders = Order.all  # Everyone sees everything!
end

# RIGHT: policy_scope filters to only the user's orders
def index
  @orders = policy_scope(Order).page(params[:page])
end
```

## Gotcha #4: The User Can Be Nil

Pundit passes `current_user` as the first argument to the policy. If the user isn't signed in and you don't handle nil, you get `NoMethodError` inside the policy.

```ruby
# WRONG: Assumes user is always present
class OrderPolicy < ApplicationPolicy
  def show?
    record.user == user || user.admin?  # NoMethodError if user is nil
  end
end

# RIGHT: Handle nil user
class OrderPolicy < ApplicationPolicy
  def show?
    return false unless user  # Guest users can't see anything

    owner? || admin?
  end

  def index?
    user.present?  # Must be signed in to list orders
  end

  private

  def admin?
    user&.admin?  # Safe navigation
  end
end
```

If you use the Null Object pattern (`GuestUser` instead of nil), this is handled automatically — but make sure `GuestUser` responds correctly to all methods the policy calls.

## Gotcha #5: Permitted Attributes Per Role

Pundit can control WHICH fields a user can update, not just WHETHER they can update:

```ruby
# app/policies/order_policy.rb
class OrderPolicy < ApplicationPolicy
  def permitted_attributes
    if user.admin?
      [:shipping_address, :notes, :status, :total, :assigned_to]
    else
      [:shipping_address, :notes]
    end
  end

  # Or per-action permitted attributes
  def permitted_attributes_for_create
    [:shipping_address, :notes, :line_items_attributes]
  end

  def permitted_attributes_for_update
    if record.pending?
      [:shipping_address, :notes]
    else
      [:notes]  # Can only edit notes after confirmation
    end
  end
end

# Controller
class OrdersController < ApplicationController
  def update
    @order = Order.find(params[:id])
    authorize @order

    if @order.update(permitted_attributes(@order))
      redirect_to @order
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # This uses Pundit's permitted_attributes — NOT params.require().permit()
  # Don't mix the two approaches
end
```

**The trap:** Using `params.require(:order).permit(:status)` in the controller bypasses Pundit's attribute control. If you use Pundit for permitted attributes, use `permitted_attributes(@order)` everywhere — don't mix approaches.

## Gotcha #6: Testing Policies

Policies are plain Ruby — test them directly without HTTP:

```ruby
# spec/policies/order_policy_spec.rb
RSpec.describe OrderPolicy do
  subject { described_class.new(user, order) }

  let(:order) { build_stubbed(:order, user: owner) }
  let(:owner) { build_stubbed(:user) }

  context "when user is the owner" do
    let(:user) { owner }

    it { is_expected.to permit_action(:show) }
    it { is_expected.to permit_action(:update) }
    it { is_expected.to permit_action(:destroy) }
  end

  context "when user is an admin" do
    let(:user) { build_stubbed(:user, role: :admin) }

    it { is_expected.to permit_action(:show) }
    it { is_expected.to permit_action(:update) }
    it { is_expected.to permit_action(:destroy) }
  end

  context "when user is a stranger" do
    let(:user) { build_stubbed(:user) }

    it { is_expected.not_to permit_action(:show) }
    it { is_expected.not_to permit_action(:update) }
    it { is_expected.not_to permit_action(:destroy) }
  end

  context "when user is nil (guest)" do
    let(:user) { nil }

    it { is_expected.not_to permit_action(:show) }
    it { is_expected.not_to permit_action(:create) }
  end

  # Testing scopes
  describe "Scope" do
    let!(:own_order) { create(:order, user: user) }
    let!(:other_order) { create(:order) }
    let(:user) { create(:user) }

    it "returns only the user's orders" do
      scope = described_class::Scope.new(user, Order).resolve
      expect(scope).to include(own_order)
      expect(scope).not_to include(other_order)
    end
  end
end
```

Add `pundit-matchers` gem for the `permit_action` syntax:

```ruby
# Gemfile (test group)
gem 'pundit-matchers'
```

## Gotcha #7: Views — Checking Permissions

```ruby
# In views, use policy() to check permissions
<% if policy(@order).update? %>
  <%= link_to "Edit", edit_order_path(@order) %>
<% end %>

<% if policy(@order).destroy? %>
  <%= button_to "Delete", order_path(@order), method: :delete %>
<% end %>

# For collection-level checks
<% if policy(Order).create? %>
  <%= link_to "New Order", new_order_path %>
<% end %>

# DON'T check roles directly in views
# WRONG:
<% if current_user.admin? %>
  <%= link_to "Edit", edit_order_path(@order) %>
<% end %>
# This duplicates policy logic. If admin rules change, you update the policy AND the view.
```

## Do's and Don'ts Summary

**DO:**
- Add `verify_authorized` and `verify_policy_scoped` after_actions immediately
- Default all permissions to `false` in `ApplicationPolicy`
- Handle nil user in every policy method
- Use `policy_scope` for collections, `authorize` for single records
- Test policies directly — they're plain Ruby, no HTTP needed
- Use `policy()` in views instead of role checks

**DON'T:**
- Don't forget to `authorize` in every controller action (or `skip_authorization` explicitly)
- Don't authorize the class when you mean the instance
- Don't mix `params.permit()` with Pundit's `permitted_attributes`
- Don't put authorization logic in controllers or views — keep it in policies
- Don't check `current_user.admin?` in views — use `policy(@record).action?`
- Don't assume user is present in policy methods — always guard for nil
