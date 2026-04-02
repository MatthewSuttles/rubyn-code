# SOLID: Single Responsibility Principle (SRP)

## Pattern

A class should have one — and only one — reason to change. Every class encapsulates one concept, one actor's requirements, or one axis of change. When requirements from different stakeholders would cause the same class to change, split it.

```ruby
# GOOD: Each class has one reason to change

# Reason to change: how orders are persisted
class Order < ApplicationRecord
  belongs_to :user
  has_many :line_items, dependent: :destroy

  validates :shipping_address, presence: true

  def total
    line_items.sum { |li| li.quantity * li.unit_price }
  end
end

# Reason to change: how order totals are calculated (tax rules, discounts)
class Orders::TotalCalculator
  def initialize(order)
    @order = order
  end

  def call
    subtotal = @order.line_items.sum { |li| li.quantity * li.unit_price }
    tax = TaxService.calculate(subtotal, @order.shipping_address)
    discount = DiscountService.calculate(subtotal, @order.user)
    subtotal + tax - discount
  end
end

# Reason to change: how order confirmations are formatted and delivered
class Orders::ConfirmationNotifier
  def initialize(order)
    @order = order
  end

  def call
    OrderMailer.confirmation(@order).deliver_later
    SmsNotifier.send(@order.user.phone, "Order #{@order.reference} confirmed!") if @order.user.sms_enabled?
  end
end

# Reason to change: how order data is exported
class Orders::CsvExporter
  HEADERS = %w[reference customer total status created_at].freeze

  def call(orders)
    CSV.generate(headers: true) do |csv|
      csv << HEADERS
      orders.each { |order| csv << row(order) }
    end
  end

  private

  def row(order)
    [order.reference, order.user.email, order.total, order.status, order.created_at.iso8601]
  end
end
```

The controller orchestrates, each specialist does its job:

```ruby
class OrdersController < ApplicationController
  def create
    @order = current_user.orders.build(order_params)
    @order.total = Orders::TotalCalculator.new(@order).call

    if @order.save
      Orders::ConfirmationNotifier.new(@order).call
      redirect_to @order, notice: "Order placed."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def export
    orders = current_user.orders.recent
    csv = Orders::CsvExporter.new.call(orders)
    send_data csv, filename: "orders-#{Date.current}.csv"
  end
end
```

## Why This Is Good

- **Changes are isolated.** Tax law changes? Modify `TotalCalculator`. Email template changes? Modify `ConfirmationNotifier`. Neither change touches the Order model, the other service, or the controller.
- **Smaller classes are easier to understand.** A developer opening `CsvExporter` knows it does one thing. They don't need to scroll past tax calculations and email logic to find the export code.
- **Easier to test.** Test `TotalCalculator` with unit tests against various tax/discount scenarios. Test `ConfirmationNotifier` by asserting emails are enqueued. Each test file is focused and fast.
- **Team-friendly.** Developer A works on tax calculation while Developer B works on notifications. No merge conflicts because the changes are in separate files.
- **Reusable.** `TotalCalculator` can be used in the controller, in a background job, in an API endpoint, and in an admin panel. If calculation lived inside the controller, it couldn't be reused.

## Anti-Pattern

A god class that handles persistence, calculation, notification, and export:

```ruby
class Order < ApplicationRecord
  belongs_to :user
  has_many :line_items

  after_create :send_confirmation_email
  after_create :send_sms_notification
  after_update :recalculate_total

  def calculate_total
    subtotal = line_items.sum { |li| li.quantity * li.unit_price }
    tax = subtotal * tax_rate_for(shipping_address)
    discount = loyalty_discount_for(user)
    self.total = subtotal + tax - discount
  end

  def tax_rate_for(address)
    case address.state
    when "CA" then 0.0725
    when "TX" then 0.0625
    when "NY" then 0.08
    else 0.05
    end
  end

  def loyalty_discount_for(user)
    return 0 unless user.loyalty_tier == :gold
    total * 0.1
  end

  def send_confirmation_email
    OrderMailer.confirmation(self).deliver_later
  end

  def send_sms_notification
    return unless user.sms_enabled?
    SmsClient.send(user.phone, "Order #{reference} confirmed!")
  end

  def to_csv
    [reference, user.email, total, status, created_at.iso8601].join(",")
  end

  def self.export_csv(orders)
    headers = "reference,customer,total,status,created_at\n"
    headers + orders.map(&:to_csv).join("\n")
  end
end
```

## Why This Is Bad

- **Four reasons to change in one class.** Tax rules, notification channels, export format, and persistence logic are all tangled together. A change to tax rates risks breaking CSV export because they share the same file.
- **500+ lines.** This Order model is headed toward 500 lines as each responsibility grows. Adding international tax, promo codes, push notifications, and PDF export will push it past 1,000.
- **Callbacks hide side effects.** `after_create :send_sms_notification` silently sends texts. Creating an order in tests, seeds, or the console triggers SMS delivery.
- **Untestable in isolation.** Testing `tax_rate_for` requires an Order instance. Testing `send_confirmation_email` requires a saved order. Everything is coupled to the model lifecycle.
- **Violates Open/Closed.** Adding a new notification channel (push, Slack) means modifying the Order class. With SRP, you modify the Notifier class or add a new one — the Order never changes.

## When To Apply

- **A class is changing for multiple reasons.** If your last 5 commits to `order.rb` were: fix tax calculation, update email template, add CSV header, fix discount logic — that's 4 different responsibilities.
- **A class is longer than ~100 lines.** Length isn't a hard rule, but it's a signal. A 200-line model usually has at least 2 responsibilities that could be extracted.
- **You describe a class with "and."** "The Order class persists data AND calculates totals AND sends notifications AND exports CSV." Each "and" is a candidate for extraction.
- **Different team members frequently edit the same file.** Merge conflicts on a model file are a sign that multiple concerns are competing for the same space.

## When NOT To Apply

- **Don't extract prematurely.** A 30-line model with validations and 2 scopes has one responsibility (data access). Don't split it into 4 classes for theoretical purity.
- **Simple derived values belong on the model.** `def full_name; "#{first_name} #{last_name}"; end` is fine on User. It's a data representation concern, not a separate responsibility.
- **Don't create single-method classes for trivial operations.** A `StringCapitalizer` class is over-engineering. SRP means one *responsibility*, not one *method*.

## Edge Cases

**How do you identify responsibilities?**
Ask: "Who would request this change?" If the answer is different people or departments (accounting wants tax changes, marketing wants email changes, ops wants export changes), those are different responsibilities.

**Rails models seem to violate SRP by default:**
ActiveRecord models combine data access, validation, association management, and query interface. This is an intentional framework trade-off. The SRP boundary in Rails is: models own persistence and validation, everything else is extracted. Don't fight the framework — work within it.

**Service objects can also violate SRP:**
A `ProcessOrderService` that calculates totals, sends emails, AND updates inventory violates SRP just as badly as a fat model. Each step should be its own service, orchestrated by a coordinator.
