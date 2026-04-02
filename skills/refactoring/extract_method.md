# Refactoring: Extract Method

## Pattern

When a method is too long or a code fragment needs a comment to explain what it does, extract that fragment into a method whose name explains the intent. The extracted method replaces the comment.

```ruby
# BEFORE: Long method with inline comments explaining sections
class Orders::InvoiceGenerator
  def generate(order)
    # Calculate line item totals
    line_totals = order.line_items.map do |item|
      {
        name: item.product.name,
        quantity: item.quantity,
        unit_price: item.unit_price,
        total: item.quantity * item.unit_price
      }
    end

    # Calculate subtotal
    subtotal = line_totals.sum { |lt| lt[:total] }

    # Apply discount if applicable
    discount = 0
    if order.discount_code.present?
      discount_record = Discount.find_by(code: order.discount_code)
      if discount_record&.active?
        discount = case discount_record.discount_type
                   when "percentage" then subtotal * (discount_record.value / 100.0)
                   when "fixed" then discount_record.value
                   else 0
                   end
      end
    end

    # Calculate tax
    tax_rate = TaxRate.for(order.shipping_address.state)
    tax = (subtotal - discount) * tax_rate

    # Build invoice
    {
      order_reference: order.reference,
      line_items: line_totals,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: subtotal - discount + tax,
      generated_at: Time.current
    }
  end
end
```

```ruby
# AFTER: Each section extracted into a named method
class Orders::InvoiceGenerator
  def generate(order)
    line_totals = itemize(order.line_items)
    subtotal = sum_totals(line_totals)
    discount = calculate_discount(order.discount_code, subtotal)
    tax = calculate_tax(order.shipping_address, subtotal - discount)

    build_invoice(order, line_totals:, subtotal:, discount:, tax:)
  end

  private

  def itemize(line_items)
    line_items.map do |item|
      {
        name: item.product.name,
        quantity: item.quantity,
        unit_price: item.unit_price,
        total: item.quantity * item.unit_price
      }
    end
  end

  def sum_totals(line_totals)
    line_totals.sum { |lt| lt[:total] }
  end

  def calculate_discount(code, subtotal)
    return 0 if code.blank?

    discount = Discount.active.find_by(code: code)
    return 0 unless discount

    case discount.discount_type
    when "percentage" then subtotal * (discount.value / 100.0)
    when "fixed" then discount.value
    else 0
    end
  end

  def calculate_tax(address, taxable_amount)
    rate = TaxRate.for(address.state)
    taxable_amount * rate
  end

  def build_invoice(order, line_totals:, subtotal:, discount:, tax:)
    {
      order_reference: order.reference,
      line_items: line_totals,
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: subtotal - discount + tax,
      generated_at: Time.current
    }
  end
end
```

## Why This Is Good

- **The public method reads like a summary.** `generate` is 5 lines that describe the algorithm at a high level: itemize, sum, discount, tax, build. You can understand the entire flow without reading implementation details.
- **Each private method has one purpose and a descriptive name.** `calculate_discount` replaces 8 lines and a comment. The method name IS the comment — and it can't go stale.
- **Independently testable.** You can test `calculate_discount` with various codes, types, and amounts without generating an entire invoice.
- **Reusable.** If another part of the app needs discount calculation, `calculate_discount` is available. Inline code in a long method is not.
- **Safe to refactor further.** `calculate_discount` is now isolated. Replacing the case statement with polymorphism is straightforward.

## Related Refactoring: Replace Temp with Query

When a temporary variable holds a computed value that could be a method call, replace the variable with a method. This makes the computation reusable and the code more readable.

```ruby
# BEFORE: Temporary variables
def price
  base_price = quantity * unit_price
  discount_factor = if base_price > 1000
                      0.95
                    elsif base_price > 500
                      0.98
                    else
                      1.0
                    end
  base_price * discount_factor
end

# AFTER: Replace temps with query methods
def price
  base_price * discount_factor
end

private

def base_price
  quantity * unit_price
end

def discount_factor
  if base_price > 1000
    0.95
  elsif base_price > 500
    0.98
  else
    1.0
  end
end
```

## When To Apply

- **A method is longer than 10 lines.** Extract until the public method is a readable summary.
- **You write a comment to explain a section.** The comment is the method name. Extract the section and delete the comment.
- **The same code fragment appears in multiple methods.** Extract once, call from both places.
- **A conditional body is more than 2-3 lines.** Extract the body into a method named for what it does, not how:

```ruby
# Before
if order.total > 500 && order.user.loyalty_tier == :gold && !order.used_promo?
  # ... 5 lines applying VIP discount
end

# After
apply_vip_discount(order) if eligible_for_vip_discount?(order)
```

## When NOT To Apply

- **The method is already 3-5 clear lines.** Don't extract a 2-line block into a method for purity. Extract for clarity, not for line count.
- **The extracted method would need 5+ parameters.** Too many parameters suggest the method needs an object, not an extraction. Consider an Introduce Parameter Object refactoring first.
- **The code is only used once and is already clear.** Extraction adds a level of indirection. If the inline code reads naturally, leave it.
