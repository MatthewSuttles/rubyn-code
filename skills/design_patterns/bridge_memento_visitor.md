# Design Pattern: Bridge

## Pattern

Separate an abstraction from its implementation so the two can vary independently. In Ruby, this means composing objects rather than inheriting — passing the implementation as a dependency.

```ruby
# The "abstraction" — what the caller interacts with
class NotificationSender
  def initialize(transport:, formatter:)
    @transport = transport    # HOW to send (email, SMS, push)
    @formatter = formatter    # HOW to format (plain, HTML, markdown)
  end

  def send(user, event)
    message = @formatter.format(event)
    @transport.deliver(user, message)
  end
end

# Transports (one dimension of variation)
class EmailTransport
  def deliver(user, message)
    NotificationMailer.send(to: user.email, body: message).deliver_later
  end
end

class SmsTransport
  def deliver(user, message)
    SmsClient.send(user.phone, message.truncate(160))
  end
end

# Formatters (another dimension of variation)
class PlainFormatter
  def format(event)
    "#{event.title}: #{event.description}"
  end
end

class HtmlFormatter
  def format(event)
    "<h2>#{event.title}</h2><p>#{event.description}</p>"
  end
end

# Mix and match independently — 2 transports × 2 formatters = 4 combinations
# Without Bridge, you'd need: EmailPlainNotifier, EmailHtmlNotifier,
# SmsPlainNotifier, SmsHtmlNotifier — and N×M more as you add options

sender = NotificationSender.new(transport: EmailTransport.new, formatter: HtmlFormatter.new)
sender.send(user, order_confirmed_event)
```

**When to use:** When you have two or more dimensions of variation that would otherwise create an explosion of subclasses.

---

# Design Pattern: Memento

## Pattern

Capture an object's internal state so it can be restored later, without exposing the internals. Useful for undo, versioning, and audit trails.

```ruby
# Memento — a frozen snapshot of state
class OrderMemento
  attr_reader :state, :created_at

  def initialize(order)
    @state = {
      status: order.status,
      total: order.total,
      shipping_address: order.shipping_address,
      discount_amount: order.discount_amount,
      notes: order.notes
    }.freeze
    @created_at = Time.current
    freeze
  end
end

# Originator — the object that creates and restores from mementos
class Order < ApplicationRecord
  def save_snapshot
    OrderMemento.new(self)
  end

  def restore_from(memento)
    assign_attributes(memento.state)
    save!
  end
end

# Caretaker — manages the history of mementos
class OrderHistory
  def initialize
    @snapshots = []
  end

  def push(memento)
    @snapshots.push(memento)
  end

  def pop
    @snapshots.pop
  end

  def peek
    @snapshots.last
  end

  def size
    @snapshots.size
  end
end

# Usage — admin makes changes with undo support
history = OrderHistory.new
order = Order.find(params[:id])

# Save state before changes
history.push(order.save_snapshot)
order.update!(status: :shipped, notes: "Expedited shipping")

# Oops, wrong order — undo
previous = history.pop
order.restore_from(previous)
# Order is back to its previous state
```

**When to use:** Undo/redo, draft saving, version history, audit trails where you need to restore previous state.

**Rails built-in alternative:** The `paper_trail` gem provides automatic versioning with mementos stored in the database.

---

# Design Pattern: Visitor

## Pattern

Separate an algorithm from the objects it operates on. Define operations in visitor objects, and let each element "accept" the visitor. This lets you add new operations without modifying the element classes.

```ruby
# Elements — domain objects that accept visitors
class Order < ApplicationRecord
  def accept(visitor)
    visitor.visit_order(self)
  end
end

class LineItem < ApplicationRecord
  def accept(visitor)
    visitor.visit_line_item(self)
  end
end

class Discount < ApplicationRecord
  def accept(visitor)
    visitor.visit_discount(self)
  end
end

# Visitor 1: Calculate tax differently per element type
class TaxCalculatorVisitor
  attr_reader :total_tax

  def initialize(tax_rate:)
    @tax_rate = tax_rate
    @total_tax = 0
  end

  def visit_order(order)
    order.line_items.each { |item| item.accept(self) }
    order.discounts.each { |discount| discount.accept(self) }
  end

  def visit_line_item(item)
    @total_tax += (item.quantity * item.unit_price * @tax_rate).round
  end

  def visit_discount(discount)
    @total_tax -= (discount.amount * @tax_rate).round
  end
end

# Visitor 2: Export elements to different formats
class CsvExportVisitor
  attr_reader :rows

  def initialize
    @rows = [%w[type reference amount]]
  end

  def visit_order(order)
    @rows << ["order", order.reference, order.total]
    order.line_items.each { |item| item.accept(self) }
  end

  def visit_line_item(item)
    @rows << ["line_item", item.product.name, item.quantity * item.unit_price]
  end

  def visit_discount(discount)
    @rows << ["discount", discount.code, -discount.amount]
  end

  def to_csv
    @rows.map { |row| row.join(",") }.join("\n")
  end
end

# Usage — different operations, same elements
tax_visitor = TaxCalculatorVisitor.new(tax_rate: 0.08)
order.accept(tax_visitor)
tax_visitor.total_tax  # => calculated tax

csv_visitor = CsvExportVisitor.new
order.accept(csv_visitor)
csv_visitor.to_csv  # => CSV string
```

**When to use:** When you need multiple unrelated operations on a set of element types, and you don't want to pollute the element classes with every operation. Common in compilers, report generators, and data exporters.

**When NOT to use:** In most Rails apps. Visitor is powerful but heavyweight. If you have 2-3 operations, methods on the models or service objects are simpler. Visitor shines when you have 5+ operations across 5+ element types.

---

## Ruby Idiomatic Alternative to Visitor

Ruby's duck typing often makes the Visitor pattern unnecessary. Instead of the formal accept/visit protocol, use polymorphic method dispatch:

```ruby
# Simpler Ruby approach — no accept/visit ceremony
class ReportGenerator
  def generate(elements)
    elements.each do |element|
      case element
      when Order then process_order(element)
      when LineItem then process_line_item(element)
      when Discount then process_discount(element)
      end
    end
  end

  private

  def process_order(order) = # ...
  def process_line_item(item) = # ...
  def process_discount(discount) = # ...
end
```

This is less "pure" OOP but more idiomatic Ruby. Use the formal Visitor when the element hierarchy is stable but operations change frequently.
