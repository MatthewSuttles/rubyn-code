# Ruby: Modules

## Pattern

Modules serve two distinct purposes in Ruby: namespacing and behavior sharing. Use namespacing modules to organize related classes. Use mixins (`include`/`extend`/`prepend`) to share behavior across unrelated classes — but only when that behavior is truly reusable and doesn't couple the classes together.

**Namespacing — grouping related classes:**

```ruby
# app/services/orders/create_service.rb
module Orders
  class CreateService
    def self.call(params, user)
      new(params, user).call
    end
    # ...
  end
end

# app/services/orders/cancel_service.rb
module Orders
  class CancelService
    def self.call(order, reason:)
      new(order, reason:).call
    end
    # ...
  end
end

# Usage: clear, organized, discoverable
Orders::CreateService.call(params, user)
Orders::CancelService.call(order, reason: "customer_request")
```

**Behavior sharing — reusable capabilities:**

```ruby
# app/models/concerns/sluggable.rb
module Sluggable
  extend ActiveSupport::Concern

  included do
    before_validation :generate_slug, on: :create
    validates :slug, presence: true, uniqueness: true
  end

  def to_param
    slug
  end

  private

  def generate_slug
    self.slug ||= name&.parameterize
  end
end

# Used in unrelated models that share the same capability
class Product < ApplicationRecord
  include Sluggable
end

class Category < ApplicationRecord
  include Sluggable
end
```

**`include` vs `extend` vs `prepend`:**

```ruby
module Logging
  def perform(*args)
    Rails.logger.info("Starting #{self.class.name}")
    result = super  # Calls the original method
    Rails.logger.info("Completed #{self.class.name}")
    result
  end
end

# prepend: Inserts BEFORE the class in the method lookup chain
# The module's method runs first, calls super to reach the class method
class ImportJob
  prepend Logging

  def perform(file_path)
    CSV.foreach(file_path) { |row| process(row) }
  end
end

# include: Inserts AFTER the class in the lookup chain
# Provides methods the class can call, but doesn't wrap existing methods
class User < ApplicationRecord
  include Sluggable  # Adds generate_slug, to_param to instances
end

# extend: Adds methods as CLASS methods, not instance methods
module Findable
  def find_by_slug(slug)
    find_by!(slug: slug)
  end
end

class Product < ApplicationRecord
  extend Findable  # Product.find_by_slug("widget")
end
```

## Why This Is Good

- **Namespacing prevents collisions.** `Orders::CreateService` and `Users::CreateService` coexist cleanly. Without namespacing, you'd need `CreateOrderService` and `CreateUserService` — longer names, flatter structure.
- **Namespacing aids discovery.** `ls app/services/orders/` shows every operation available for orders. The file system mirrors the module structure.
- **Mixins share behavior without inheritance.** `Sluggable` can be included in Product, Category, and Article without any of them inheriting from a common base class. This avoids fragile inheritance hierarchies.
- **`prepend` enables clean wrapping.** Adding logging, caching, or instrumentation around a method without modifying the original class. `super` calls the original implementation.
- **`ActiveSupport::Concern` simplifies Rails mixins.** It handles `included` blocks, class methods, and dependency resolution cleanly.

## Anti-Pattern

Using modules as dumping grounds for loosely related methods:

```ruby
# app/models/concerns/order_helpers.rb
module OrderHelpers
  extend ActiveSupport::Concern

  def calculate_total
    line_items.sum { |li| li.quantity * li.unit_price }
  end

  def apply_discount(code)
    discount = Discount.find_by(code: code)
    self.discount_amount = discount.calculate(total)
  end

  def send_confirmation
    OrderMailer.confirmation(self).deliver_later
  end

  def sync_to_warehouse
    WarehouseApi.new.sync(self)
  end

  def generate_invoice_pdf
    InvoicePdfGenerator.new(self).generate
  end

  included do
    after_create :send_confirmation
    after_update :sync_to_warehouse, if: :saved_change_to_status?
  end
end
```

## Why This Is Bad

- **Junk drawer module.** Calculation, discounts, email, warehouse API, and PDF generation are unrelated responsibilities dumped into one module. The module has no cohesive purpose.
- **Hidden the fat model problem.** Moving 50 lines from the model into a concern doesn't fix the design — it just hides the bloat in a different file. The model is still doing too much.
- **Tight coupling.** Any class that includes `OrderHelpers` gets email sending, warehouse syncing, and PDF generation — even if it only needed `calculate_total`.
- **Callbacks hiding in concerns.** `after_create :send_confirmation` is invisible when reading the model. The concern silently adds behavior that triggers on every create.
- **Not reusable.** Despite being a module, `OrderHelpers` only works with orders. No other model can include it. It's not actually shared behavior.

## When To Apply

**Use namespacing modules when:**
- You have multiple classes that operate on the same domain concept (`Orders::CreateService`, `Orders::CancelService`, `Orders::SearchQuery`)
- You want to organize files in a directory structure that mirrors the module hierarchy
- You need to avoid class name collisions

**Use behavior-sharing modules when:**
- The behavior is genuinely used by 2+ unrelated classes (Sluggable, Searchable, Auditable)
- The behavior is self-contained — it doesn't depend on the including class having specific methods or attributes (beyond a clear, documented contract)
- The behavior is about capability ("this object is sluggable") not identity ("this object is an order")

**Use `prepend` when:**
- You need to wrap an existing method with before/after behavior (logging, caching, instrumentation, retry logic)
- You want `super` to call the original implementation

## When NOT To Apply

- **Don't use modules to split a fat model into files.** If your model is 500 lines and you split it into 5 concerns of 100 lines, you still have a 500-line model — it's just harder to read because it's scattered across files.
- **Don't create a concern for behavior used by only one class.** A concern that's included in exactly one model is just indirection. Keep the methods in the model.
- **Don't use `extend` when you mean `include`.** Extending adds class methods. Including adds instance methods. Confusing them causes `NoMethodError` at runtime.
- **Don't use `module_function` in Rails concerns.** It makes methods both instance and module methods, which creates confusing dual interfaces.

## Edge Cases

**Concern depends on the including class having specific attributes:**
Document the contract explicitly. Use a class method or a runtime check:

```ruby
module Publishable
  extend ActiveSupport::Concern

  included do
    raise "#{self} must have a published_at column" unless column_names.include?("published_at")

    scope :published, -> { where.not(published_at: nil) }
    scope :draft, -> { where(published_at: nil) }
  end

  def publish!
    update!(published_at: Time.current)
  end
end
```

**Multiple modules define the same method:**
Ruby uses the method lookup chain. The last included module wins. Use `prepend` if you need explicit ordering with `super` delegation.

**When to use `ActiveSupport::Concern` vs plain modules:**
Use `Concern` in Rails apps when you need `included` blocks, class methods, or concern dependencies. Use plain modules in pure Ruby, gems, or when the module only adds instance methods.
