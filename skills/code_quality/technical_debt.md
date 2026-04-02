# Code Quality: Technical Debt

## Core Principle

Technical debt is the gap between the code you have and the code you'd write if you had unlimited time. Like financial debt, it accrues interest — every feature built on top of debt takes longer and introduces more bugs. The goal isn't zero debt (that's impossible) — it's managing it deliberately.

## Types of Technical Debt

### Deliberate, Prudent ("We'll ship this shortcut and clean it up next sprint")
```ruby
# We know this should be a service object, but shipping the feature matters more today
def create
  @order = current_user.orders.build(order_params)
  @order.total = @order.line_items.sum { |li| li.quantity * li.unit_price }
  # TODO: Extract to Orders::CreateService — ticket PROJ-123
  if @order.save
    OrderMailer.confirmation(@order).deliver_later
    redirect_to @order
  else
    render :new, status: :unprocessable_entity
  end
end
```
This is fine IF you track it and pay it back. The TODO references a real ticket. The code works. The shortcut is documented.

### Deliberate, Reckless ("We don't have time for tests")
```ruby
# No tests, no error handling, bare rescue, hardcoded values
def process_payment
  Stripe::Charge.create(amount: params[:amount], source: params[:token])
  redirect_to success_path
rescue
  redirect_to failure_path
end
```
This debt compounds fast. The bare rescue hides bugs. No tests means no safety net for changes. Hardcoded Stripe calls can't be tested.

### Inadvertent ("We didn't know better at the time")
```ruby
# Written before the team learned about service objects
# 200-line controller that grew organically
class OrdersController < ApplicationController
  def create
    # 50 lines of business logic
  end

  def update
    # 40 lines of business logic
  end
  # ...
end
```
This isn't bad intent — it's a natural consequence of learning. The team knows better now. Refactoring it is an investment, not a punishment.

## When to Pay Down Debt

### Pay now (before the next feature):
- **You're about to modify the same code.** If the next ticket touches `OrdersController#create`, refactor it first. The boy scout rule: leave the code better than you found it.
- **The debt blocks the feature.** If you can't add pagination because the query is a mess, fix the query.
- **It's causing production incidents.** The bare rescue silently swallowing errors? Fix it before the next outage.
- **It's slowing down every developer.** A 500-line model that everyone edits — refactoring it saves cumulative hours across the team.

### Pay later (track it, don't fix it now):
- **The code works and isn't being modified.** A messy module that nobody touches doesn't accrue interest.
- **The refactoring is large and risky.** Rewriting the authentication system requires planning, not a drive-by fix.
- **You're about to delete the feature.** Don't polish code that's being removed next month.

### Don't pay at all:
- **Speculative generality.** "We should make this more flexible" — but nobody has asked for flexibility. Don't refactor toward imagined future requirements.
- **Style preferences.** Rewriting working code because "I'd write it differently" isn't paying debt — it's churn.

## Tracking Debt

```ruby
# In code: TODO with a ticket reference
# TODO: Extract discount calculation to DiscountService — PROJ-456
# TODO: Replace N+1 query with includes — PROJ-789

# NOT useful: TODOs without context
# TODO: Fix this
# TODO: Refactor later
# TODO: This is bad
```

### Debt Inventory (for the team)

| Location | Smell | Impact | Effort | Priority |
|---|---|---|---|---|
| `OrdersController#create` | Fat controller (50 lines) | Medium — every order change touches this | Small — extract to service | **Next sprint** |
| `User` model | 300 lines, 5 concerns | High — every dev edits this daily | Large — needs planning | **Schedule** |
| `spec/` | 40% use `create` where `build_stubbed` works | Medium — slow CI | Medium — incremental | **Boy scout** |
| `Legacy::Importer` | No tests, bare rescue | Low — runs once per month | Medium | **Track, don't fix** |

## Refactoring Strategies

### Boy Scout Rule (Incremental)
Every PR that touches a file leaves it slightly better. Rename a variable, extract a method, add a missing test. Small improvements compound.

### Strangler Fig (Gradual Replacement)
Build the new system alongside the old one. Route new traffic to the new system. Eventually shut off the old one. Works for large rewrites (new API version, new auth system).

```ruby
# Old: everything in the controller
class OrdersController
  def create
    # 50 lines of legacy code
  end
end

# New: service object handles new code paths
class OrdersController
  def create
    if Feature.enabled?(:new_order_flow, current_user)
      result = Orders::CreateService.call(order_params, current_user)
      # ...
    else
      # Legacy path — will be removed once new flow is stable
      # ...
    end
  end
end
```

### Dedicated Refactoring Sprint
Reserve 10-20% of sprint capacity for debt reduction. Pick the highest-impact items from the debt inventory. This works for teams that can't justify "refactoring PRs" individually but can justify a planned investment.

## Rubyn's Role in Debt Management

When Rubyn reviews code, it identifies debt using the code smells vocabulary (Long Method, Feature Envy, Shotgun Surgery, etc.) and gives each finding a severity. This turns vague "this code is messy" feelings into specific, actionable items that can be tracked and prioritized.

When Rubyn refactors, it pays down the specific debt you point it at — extracting the service object, fixing the N+1, replacing the bare rescue — while preserving behavior. It's a tool for incremental improvement, not a magic "fix everything" button.

## The Key Insight

The most expensive code isn't code with debt — it's code with *untracked* debt. A TODO with a ticket is managed. A 500-line controller that everyone complains about but nobody documents is a slowly growing crisis. Track it, prioritize it, pay it down incrementally.
