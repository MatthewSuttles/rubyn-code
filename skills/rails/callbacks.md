# Rails: ActiveRecord Callbacks

## Pattern

Use callbacks only for concerns that are intrinsic to data integrity — things that must always happen whenever the record changes, regardless of context. Everything else belongs in service objects.

Safe callback use cases:

```ruby
class Order < ApplicationRecord
  # GOOD: Normalizing data before save — this should always happen
  before_validation :normalize_email
  before_validation :generate_reference, on: :create

  # GOOD: Maintaining data integrity
  before_save :calculate_total, if: :line_items_changed?

  # GOOD: Cleaning up owned resources
  after_destroy :purge_attached_files

  private

  def normalize_email
    self.email = email&.downcase&.strip
  end

  def generate_reference
    self.reference ||= "ORD-#{SecureRandom.hex(6).upcase}"
  end

  def calculate_total
    self.total = line_items.sum { |item| item.quantity * item.unit_price }
  end

  def purge_attached_files
    receipt.purge_later if receipt.attached?
  end
end
```

## Why This Is Good

- **Predictable.** Callbacks for data normalization and integrity are expected behavior. Every developer knows `before_validation` might downcase an email. Nobody expects `after_create` to charge a credit card.
- **Context-independent.** Normalizing an email should happen whether the record is created via web form, API, console, seed file, or test factory. That's intrinsic to the data.
- **No surprises in tests.** When a test creates an Order, it gets a reference number and a calculated total. It does NOT send emails, charge cards, or hit external APIs.
- **Safe to call from anywhere.** `Order.create!(params)` works correctly from a controller, a Sidekiq job, a rake task, or the Rails console — because the callbacks only handle data integrity.

## Anti-Pattern

Using callbacks for business logic, side effects, and cross-model operations:

```ruby
class Order < ApplicationRecord
  after_create :send_confirmation_email
  after_create :notify_warehouse
  after_create :update_product_inventory
  after_create :award_loyalty_points
  after_create :track_analytics_event

  after_update :send_status_change_email, if: :saved_change_to_status?
  after_update :refund_if_cancelled, if: -> { saved_change_to_status?(to: "cancelled") }

  after_destroy :restore_inventory
  after_destroy :send_cancellation_email

  private

  def send_confirmation_email
    OrderMailer.confirmation(self).deliver_later
  end

  def notify_warehouse
    WarehouseApi.new.notify(order_id: id, items: line_items.map(&:sku))
  end

  def update_product_inventory
    line_items.each do |item|
      item.product.decrement!(:stock, item.quantity)
    end
  end

  def award_loyalty_points
    user.increment!(:loyalty_points, (total / 10).floor)
  end

  def track_analytics_event
    Analytics.track("order_created", order_id: id, total: total)
  end
end
```

## Why This Is Bad

- **Hidden side effects.** A developer running `Order.create!(params)` in the console to fix a data issue accidentally sends a confirmation email, notifies a warehouse, decrements inventory, awards loyalty points, and fires an analytics event. None of this is visible from the call site.
- **Tests become slow and fragile.** Every test that creates an order triggers the full callback chain. You need to stub mailers, mock external APIs, and create associated products with sufficient stock. Factory creation becomes a minefield.
- **Ordering problems.** Callbacks run in declaration order. If `notify_warehouse` depends on `update_product_inventory` having run first, reordering the declarations breaks the app silently.
- **Impossible to skip selectively.** You can't create an order without sending an email unless you add flags (`skip_email: true`) that pollute the model with callback control logic.
- **Transaction danger.** `after_create` runs inside the transaction. If `notify_warehouse` raises an HTTP error, the entire order creation rolls back — even though the order itself was valid.
- **Circular dependencies.** Callback A on Order updates Product stock. A callback on Product recalculates availability. That triggers a callback that touches Order again. Infinite loops are hard to debug.

## When To Apply

Use callbacks ONLY for these purposes:

- **Data normalization** — downcasing emails, stripping whitespace, formatting phone numbers, generating slugs/tokens
- **Default values** — setting a reference number, a UUID, a default status on creation
- **Derived calculations** — computing a total from line items, a full name from first + last
- **Cleanup of owned resources** — purging Active Storage attachments, removing associated cache entries
- **Counter maintenance** — only when `counter_cache` on the association isn't sufficient

The test: "If I create this record from the Rails console with no other context, should this behavior still happen?" If yes → callback. If no → service object.

## When NOT To Apply

Do NOT use callbacks for:

- **Sending emails or notifications.** These are side effects that depend on context. An order created by an admin backfill should not trigger a customer email.
- **Calling external APIs.** Webhooks, warehouse notifications, payment charges. These fail independently and should not roll back the record.
- **Modifying other models.** Updating inventory, awarding points, creating audit records. These are business logic, not data integrity.
- **Enqueuing background jobs.** Use service objects that explicitly enqueue after the primary operation succeeds.
- **Anything with `if:` conditions based on business context.** If a callback needs `if: :registering?` or `if: :from_api?`, it's not intrinsic to the data — it's business logic wearing a callback costume.

## Edge Cases

**The team already has callbacks everywhere:**
Don't rip them all out at once. When modifying a model, extract the business-logic callbacks into a service object one at a time. Leave the data-integrity callbacks in place.

**`after_commit` vs `after_create`:**
If you must trigger a side effect from a model (not recommended, but sometimes pragmatic), use `after_commit` instead of `after_create`. It runs after the transaction commits, so a failure won't roll back the record. But this is still a code smell — prefer service objects.

**Gems that require callbacks (like `acts_as_paranoid`, `paper_trail`):**
These are fine. They manage data integrity (soft deletes, audit trails) which is a legitimate callback concern. The gem handles the complexity.

**Touch callbacks (`belongs_to :order, touch: true`):**
These are fine — they maintain cache integrity and are intrinsic to the data relationship.
