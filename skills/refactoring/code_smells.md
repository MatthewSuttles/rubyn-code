# Code Smells: Recognition and Remedies

## What Are Code Smells?

Code smells are surface indicators that usually correspond to deeper design problems. They're not bugs — the code works — but they signal that the code will be increasingly painful to maintain, extend, and test. Recognizing smells is the first step; the refactoring that fixes them is the second.

## Bloaters

Smells where code has grown too large to work with effectively.

### Long Method

**Smell:** A method longer than ~10 lines, especially if it has comments explaining sections.

```ruby
# SMELL: 30+ lines doing multiple things
def process_order(params)
  # Validate
  return error("Missing address") if params[:address].blank?
  return error("No items") if params[:items].empty?

  # Create order
  order = Order.new(address: params[:address], user: current_user)
  params[:items].each do |item|
    product = Product.find(item[:id])
    order.line_items.build(product: product, quantity: item[:qty], price: product.price)
  end

  # Calculate totals
  order.subtotal = order.line_items.sum { |li| li.quantity * li.price }
  order.tax = order.subtotal * 0.08
  order.total = order.subtotal + order.tax

  # Save and notify
  order.save!
  OrderMailer.confirmation(order).deliver_later
  WarehouseService.notify(order)
  order
end
```

**Fix:** Extract Method. Each comment-delimited section becomes a named method. Or better — each section becomes a service object.

### Large Class

**Smell:** A class with 200+ lines, 15+ methods, or 7+ instance variables. In Rails, models that include 5+ concerns.

**Fix:** Extract Class. Identify clusters of methods that work together and move them into collaborator objects (service objects, value objects, query objects).

### Long Parameter List

**Smell:** A method with 4+ parameters, especially positional ones.

```ruby
# SMELL
def create_user(email, name, role, company_name, plan, referral_code, notify)

# FIX: Introduce Parameter Object or use keyword arguments
def create_user(email:, name:, role:, company_name:, plan:, referral_code: nil, notify: true)

# BETTER FIX: If parameters are always passed together, create a value object
RegistrationParams = Data.define(:email, :name, :role, :company_name, :plan, :referral_code)
def create_user(params, notify: true)
```

### Primitive Obsession

**Smell:** Using strings, integers, or hashes where a domain object would be clearer.

```ruby
# SMELL: Money as a float, address as a hash
order.total = 19.99
order.address = { street: "123 Main", city: "Austin", state: "TX", zip: "78701" }

# FIX: Replace Data Value with Object
order.total = Money.new(19_99, "USD")
order.address = Address.new(street: "123 Main", city: "Austin", state: "TX", zip: "78701")
```

Value objects have behavior — `money.to_s`, `address.full`, `money + other_money` — that primitives don't.

## Couplers

Smells where classes are too intertwined.

### Feature Envy

**Smell:** A method that uses more data from another object than from its own.

```ruby
# SMELL: This method on OrderPresenter mostly accesses user attributes
class OrderPresenter
  def shipping_label(order)
    "#{order.user.name}\n#{order.user.address.street}\n#{order.user.address.city}, #{order.user.address.state} #{order.user.address.zip}"
  end
end

# FIX: Move Method — the method belongs on Address or User
class Address
  def to_label(name)
    "#{name}\n#{street}\n#{city}, #{state} #{zip}"
  end
end

# Usage
order.user.address.to_label(order.user.name)
```

### Message Chains (Law of Demeter Violation)

**Smell:** `order.user.company.billing_address.country.tax_rate` — a long chain of navigating object relationships.

```ruby
# SMELL: Caller knows the entire object graph
tax_rate = order.user.company.billing_address.country.tax_rate

# FIX: Hide Delegate — each object only talks to its immediate neighbors
class Order
  delegate :tax_rate, to: :user, prefix: false

  # Or a dedicated method
  def applicable_tax_rate
    user.billing_tax_rate
  end
end

class User
  def billing_tax_rate
    company.billing_tax_rate
  end
end

class Company
  def billing_tax_rate
    billing_address.country_tax_rate
  end
end

# Usage
order.applicable_tax_rate
```

### Inappropriate Intimacy

**Smell:** Two classes that access each other's internal details excessively.

```ruby
# SMELL: Service reaches into order's internals
class ShippingCalculator
  def calculate(order)
    weight = order.instance_variable_get(:@total_weight)  # Accessing internals!
    order.line_items.each { |li| li.instance_variable_set(:@shipping_cost, weight * 0.5) }
  end
end

# FIX: Use public interfaces
class ShippingCalculator
  def calculate(order)
    weight = order.total_weight  # Public method
    weight * shipping_rate_per_kg
  end
end
```

## Dispensables

Smells where something isn't needed.

### Dead Code

**Smell:** Methods, variables, classes, or branches that are never executed.

```ruby
# SMELL: Method hasn't been called since 2023
def legacy_import(csv_path)
  # 40 lines of import logic
end

# SMELL: Unreachable branch
def status_label
  case status
  when "active" then "Active"
  when "inactive" then "Inactive"
  when "deleted" then "Deleted"  # status is never "deleted" — soft delete uses discarded_at
  end
end
```

**Fix:** Delete it. Version control has the history if you ever need it. Dead code creates confusion ("is this still used?"), false grep results, and maintenance burden.

### Speculative Generality

**Smell:** Abstractions, hooks, parameters, or classes that exist "in case we need them later" but have no current use.

```ruby
# SMELL: AbstractNotificationFactory that only has one subclass
class AbstractNotificationFactory
  def build(type, **opts)
    raise NotImplementedError
  end
end

class EmailNotificationFactory < AbstractNotificationFactory
  def build(type, **opts)
    # ... this is the only implementation
  end
end
```

**Fix:** Delete the abstraction. When you actually need a second factory, extract the interface then. YAGNI (You Ain't Gonna Need It).

### Duplicate Code

**Smell:** The same code structure in two or more places.

```ruby
# SMELL: Same pattern in two controllers
class OrdersController < ApplicationController
  def index
    @orders = current_user.orders
    @orders = @orders.where(status: params[:status]) if params[:status].present?
    @orders = @orders.where("created_at >= ?", params[:from]) if params[:from].present?
    @orders = @orders.page(params[:page])
  end
end

class InvoicesController < ApplicationController
  def index
    @invoices = current_user.invoices
    @invoices = @invoices.where(status: params[:status]) if params[:status].present?
    @invoices = @invoices.where("created_at >= ?", params[:from]) if params[:from].present?
    @invoices = @invoices.page(params[:page])
  end
end
```

**Fix:** Extract the filtering logic into a query object or a concern that both controllers use:

```ruby
class FilteredQuery
  def self.call(scope, params)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("created_at >= ?", params[:from]) if params[:from].present?
    scope.page(params[:page])
  end
end
```

## How Rubyn Uses This

When analyzing code, Rubyn identifies these smells and suggests the specific refactoring to fix them. The recommendation always includes the smell name, why it matters, and the concrete transformation — not just "this method is too long."
