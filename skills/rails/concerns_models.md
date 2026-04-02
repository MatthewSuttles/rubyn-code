# Rails: Model Concerns

## Pattern

Use model concerns for genuine, reusable behavior that multiple unrelated models need. A good concern adds one well-defined capability — slugging, soft deleting, auditing, searching. It has a clear contract and works without knowledge of the including model's specific attributes.

```ruby
# app/models/concerns/searchable.rb
module Searchable
  extend ActiveSupport::Concern

  included do
    scope :search, ->(query) {
      return all if query.blank?

      columns = searchable_columns.map { |col| "#{table_name}.#{col}" }
      conditions = columns.map { |col| "#{col} ILIKE :query" }.join(" OR ")
      where(conditions, query: "%#{sanitize_sql_like(query)}%")
    }
  end

  class_methods do
    def searchable_columns
      raise NotImplementedError, "#{name} must define searchable_columns"
    end
  end
end

# Usage in models — each defines what's searchable
class User < ApplicationRecord
  include Searchable

  def self.searchable_columns
    %w[name email]
  end
end

class Product < ApplicationRecord
  include Searchable

  def self.searchable_columns
    %w[name description sku]
  end
end

# Both work identically
User.search("alice")
Product.search("widget")
```

```ruby
# app/models/concerns/soft_deletable.rb
module SoftDeletable
  extend ActiveSupport::Concern

  included do
    scope :kept, -> { where(discarded_at: nil) }
    scope :discarded, -> { where.not(discarded_at: nil) }

    default_scope { kept }
  end

  def discard
    update(discarded_at: Time.current)
  end

  def undiscard
    update(discarded_at: nil)
  end

  def discarded?
    discarded_at.present?
  end
end
```

```ruby
# app/models/concerns/has_token.rb
module HasToken
  extend ActiveSupport::Concern

  included do
    before_create :generate_token
  end

  class_methods do
    def token_column
      :token
    end

    def find_by_token!(token)
      find_by!(token_column => token)
    end
  end

  private

  def generate_token
    column = self.class.token_column
    loop do
      self[column] = SecureRandom.urlsafe_base64(32)
      break unless self.class.exists?(column => self[column])
    end
  end
end
```

## Why This Is Good

- **Genuinely reusable.** `Searchable`, `SoftDeletable`, and `HasToken` work on any model. They don't know or care about order-specific, user-specific, or product-specific logic.
- **Clear contract.** `Searchable` requires the model to define `searchable_columns`. The concern raises `NotImplementedError` if the model forgets. The contract is explicit and enforced.
- **Self-contained.** Including `SoftDeletable` gives you scopes, instance methods, and a default scope. The model doesn't need to configure anything — just include and add a `discarded_at` column.
- **Tested independently.** You can write a shared example that tests the searchable behavior, then include it in User and Product specs. One test verifies the concern works; per-model tests verify the configuration.
- **Namespace isolation.** The concern defines behavior. The model defines which columns/attributes to apply it to. Neither reaches into the other's internals.

## Anti-Pattern

Using concerns to split a fat model into multiple files without actually improving the design:

```ruby
# app/models/concerns/order_calculations.rb
module OrderCalculations
  extend ActiveSupport::Concern

  def calculate_subtotal
    line_items.sum { |li| li.quantity * li.unit_price }
  end

  def calculate_tax
    subtotal * tax_rate
  end

  def calculate_shipping
    return 0 if subtotal > 100
    line_items.sum(&:weight) * 0.5
  end

  def calculate_total
    calculate_subtotal + calculate_tax + calculate_shipping
  end

  def apply_discount(code)
    discount = Discount.find_by(code: code)
    self.discount_amount = discount&.calculate(calculate_subtotal) || 0
  end
end

# app/models/concerns/order_status.rb
module OrderStatus
  extend ActiveSupport::Concern

  included do
    enum :status, { pending: 0, confirmed: 1, shipped: 2, delivered: 3, cancelled: 4 }

    after_update :handle_status_change, if: :saved_change_to_status?
  end

  def can_cancel?
    pending? || confirmed?
  end

  def can_ship?
    confirmed? && line_items.all?(&:in_stock?)
  end

  private

  def handle_status_change
    case status
    when "confirmed" then OrderMailer.confirmed(self).deliver_later
    when "shipped" then OrderMailer.shipped(self).deliver_later
    when "cancelled" then process_cancellation
    end
  end

  def process_cancellation
    line_items.each { |li| li.product.increment!(:stock, li.quantity) }
    RefundService.call(self)
  end
end

# app/models/order.rb
class Order < ApplicationRecord
  include OrderCalculations
  include OrderStatus
  include OrderNotifications
  include OrderValidations
  include OrderScopes

  # Model is now 5 lines but still has 500 lines of responsibility
end
```

## Why This Is Bad

- **Same responsibilities, different files.** The Order model still has calculations, status management, email sending, inventory management, and refund processing — they're just scattered across 5 files instead of 1. The complexity hasn't been reduced.
- **Not reusable.** `OrderCalculations` only works for orders. No other model can include it. It's not a shared capability — it's an order-specific feature hidden in a concern.
- **Harder to navigate.** A developer looking at `Order` sees 5 includes and has to open 5 files to understand what the model does. In a single file, they can scroll. With concerns, they play file hopscotch.
- **Hidden callbacks.** `OrderStatus` adds an `after_update` callback that sends emails and processes refunds. Including `OrderStatus` in the model gives you no indication that saving an order might trigger a refund.
- **Business logic in concerns.** `process_cancellation` does inventory management and calls `RefundService`. This belongs in a service object (`Orders::CancelService`), not in a model concern.

## When To Apply

Use model concerns when ALL of these are true:

1. **Multiple unrelated models** need the same behavior (at least 2, ideally 3+)
2. The behavior is a **capability** ("searchable", "sluggable", "auditable"), not a **feature** ("order calculations")
3. The concern is **self-contained** — it doesn't need to know the model's specific business logic
4. The concern has a **clear contract** — the model must provide specific columns or methods, documented explicitly

## When NOT To Apply

- **Don't use concerns to split a fat model.** If the model is too big, extract service objects, form objects, and query objects. Moving code to a concern file doesn't reduce complexity.
- **Don't create a concern used by one model.** That's just indirection. Keep the code in the model.
- **Don't put business logic in concerns.** Calculations, status transitions, payment processing, and notification sending are business logic. They belong in service objects.
- **Don't put callbacks with side effects in concerns.** If a concern adds `after_create :send_welcome_email`, every model that includes it gets that behavior — possibly unintentionally. Side-effect callbacks belong in service objects.

## Edge Cases

**Concern needs different configuration per model:**
Use class methods that the model overrides:

```ruby
module Archivable
  extend ActiveSupport::Concern

  class_methods do
    def archive_after
      30.days  # Default
    end
  end

  included do
    scope :archivable, -> { where(created_at: ..archive_after.ago) }
  end
end

class Order < ApplicationRecord
  include Archivable

  def self.archive_after
    90.days  # Override
  end
end
```

**Testing concerns:**
Use shared examples that any including model can run:

```ruby
RSpec.shared_examples "a searchable model" do
  describe ".search" do
    it "finds records matching the query" do
      matching = create(described_class.model_name.singular, name: "Rubyn Widget")
      non_matching = create(described_class.model_name.singular, name: "Other Thing")

      results = described_class.search("rubyn")
      expect(results).to include(matching)
      expect(results).not_to include(non_matching)
    end

    it "returns all records for blank query" do
      create(described_class.model_name.singular)
      expect(described_class.search("")).to eq(described_class.all)
    end
  end
end

# In each model spec
RSpec.describe User do
  it_behaves_like "a searchable model"
end

RSpec.describe Product do
  it_behaves_like "a searchable model"
end
```

**Concern vs STI (Single Table Inheritance):**
Use STI when models share a database table and have an "is-a" relationship (AdminUser is a User). Use concerns when models share behavior but have separate tables and no inheritance relationship (both User and Product are searchable, but a User is not a Product).
