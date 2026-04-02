# Code Quality: Code That Fits in Your Head

## Core Principle

The human brain can hold approximately 7 items in working memory at once. Code should be structured so that understanding any single unit (method, class, module) requires holding fewer than 7 concepts simultaneously. When code exceeds working memory limits, bugs creep in because developers can't track all the moving parts.

## The 7±2 Rule Applied to Code

### Methods: Max 7 Lines of Logic

A method should fit in your mental "scratchpad." If you can't hold the entire method in your head at once, it's too complex.

```ruby
# GOOD: 5 concepts — easily fits in working memory
# 1. Load order  2. Check editable  3. Update  4. Success path  5. Failure path
def update
  order = current_user.orders.find(params[:id])
  return head :forbidden unless order.editable?

  if order.update(order_params)
    redirect_to order, notice: "Updated."
  else
    render :edit, status: :unprocessable_entity
  end
end

# BAD: 12+ concepts — exceeds working memory
def update
  order = current_user.orders.find(params[:id])
  return head :forbidden unless order.editable?

  old_total = order.total
  order.assign_attributes(order_params)

  order.line_items.each do |item|
    product = Product.find(item.product_id)
    if product.stock < item.quantity
      order.errors.add(:base, "#{product.name} insufficient stock")
    end
    item.unit_price = product.current_price  # Price may have changed
  end

  order.subtotal = order.line_items.sum { |li| li.quantity * li.unit_price }
  order.tax = TaxService.calculate(order.subtotal, order.shipping_address)
  order.total = order.subtotal + order.tax

  if order.total != old_total && order.paid?
    difference = order.total - old_total
    if difference > 0
      Payments::ChargeService.call(order, difference)
    else
      Payments::RefundService.call(order, difference.abs)
    end
  end

  if order.errors.empty? && order.save
    OrderMailer.updated(order).deliver_later if order.total != old_total
    redirect_to order, notice: "Updated."
  else
    render :edit, status: :unprocessable_entity
  end
end
```

The second method requires tracking: order, old_total, line_items, products, stock levels, pricing changes, subtotal, tax, total, paid status, payment difference, charge vs refund, email condition, save result. That's 13+ concepts — far beyond working memory.

### Classes: Max 7 Public Methods

A class with 3-7 public methods is graspable. You can understand its entire interface at a glance. Beyond 7, you start forgetting methods while reading others.

```ruby
# GOOD: 5 public methods — clear, focused interface
class Order < ApplicationRecord
  # Queries
  scope :recent, -> { where(created_at: 30.days.ago..) }
  scope :pending, -> { where(status: :pending) }

  # Commands
  def confirm!
    current_state.confirm(self)
  end

  def cancel!(reason:)
    current_state.cancel(self, reason: reason)
  end

  # Queries
  def total
    line_items.sum { |li| li.quantity * li.unit_price }
  end

  def editable?
    pending? || confirmed?
  end
end
```

### Parameters: Max 3-4

After 4 parameters, callers start confusing argument order, even with keyword arguments. Extract a parameter object or rethink the method's responsibility.

```ruby
# GOOD: 2 parameters — trivially understandable
def send_notification(user, message)

# OK: 4 keyword parameters — manageable with names
def create_order(user:, items:, address:, payment_method:)

# BAD: 7 parameters — nobody can remember these
def create_order(user:, items:, address:, payment_method:, discount_code:, currency:, notify:)

# FIX: Extract a parameter object
OrderRequest = Data.define(:user, :items, :address, :payment_method, :discount_code, :currency, :notify)
def create_order(request)
```

### Nesting: Max 2 Levels

Each level of nesting adds a context to track. At 3+ levels, you're juggling too many conditions.

```ruby
# GOOD: 1 level of nesting
def process(order)
  return error("Empty") if order.line_items.empty?
  return error("Invalid address") unless order.address_valid?

  charge(order)
end

# BAD: 4 levels
def process(order)
  if order.line_items.any?
    if order.address_valid?
      if order.user.payment_method.present?
        if order.user.payment_method.valid?
          charge(order)
        end
      end
    end
  end
end
```

## The Transformation Priority Principle

When your code is complex, simplify in this order:

1. **Extract till you drop.** Break long methods into smaller ones until each method is 5-7 lines.
2. **Flatten conditionals.** Use guard clauses to eliminate nesting.
3. **Replace primitives with objects.** Turn strings and hashes into value objects with named methods.
4. **Replace branching with polymorphism.** Case statements on type become separate classes.
5. **Compose small objects.** Large classes become coordinators of small, focused collaborators.

## Practical Heuristics

### The Squint Test
Squint at your code. If the indentation forms a deep "V" shape (deep nesting), it needs flattening. If you see large blocks of similar-looking code, it has duplication.

### The Headline Test
Can you describe what a method does in a short headline? "Calculates order total" — good. "Validates, calculates, charges, and notifies" — too many verbs, extract.

### The Scroll Test
If a method or class requires scrolling to read in your editor, it's too long. A method should fit on screen. A class should fit in a few screens.

### The Rename Test
If you can't think of a good name for a method, it probably does too many things. A method that does one thing always has a clear name. "Process" and "handle" are signs of unfocused methods.

## When To Apply

- **Every code review.** Check: does each method fit in working memory? Can you understand it without scrolling back?
- **When you re-read code and feel confused.** If you wrote it last week and can't quickly understand it, future-you (and every teammate) will have the same problem.
- **When modifying existing code.** Before adding a feature to a 50-line method, extract until the method is small, then add the feature to the appropriate extracted method.

## When NOT To Apply

- **Don't optimize for line count.** A 12-line method that reads clearly is better than 4 methods of 3 lines each where you lose the overall flow.
- **Don't extract if names don't improve clarity.** `do_step_1`, `do_step_2` are worse than inline code. Extract when the method name adds meaning.
- **Configuration and setup code is naturally longer.** A Rails initializer or a factory definition doesn't need to be 7 lines. The heuristics apply to logic, not configuration.

## Connection to Other Principles

This principle underpins everything else:
- **SRP** keeps classes small enough to fit in your head
- **Extract Method** keeps methods small enough to fit in your head
- **Guard Clauses** reduce nesting to fit in your head
- **Value Objects** replace primitives so you think in domain terms, not data types
- **Service Objects** keep controllers small enough to fit in your head

The goal is always the same: any developer should be able to read a unit of code and fully understand it without external aids, notes, or extensive scrolling.
