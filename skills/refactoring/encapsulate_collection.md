# Refactoring: Encapsulate Collection

## Pattern

When a class exposes a raw collection (array, hash) through a getter, external code can modify it without the owning class knowing. Encapsulate the collection by providing specific methods for adding, removing, and querying — never exposing the raw collection.

```ruby
# BEFORE: Exposed collection — anyone can mutate it
class Order
  attr_accessor :line_items

  def initialize
    @line_items = []
  end

  def total
    @line_items.sum { |item| item.quantity * item.unit_price }
  end
end

order = Order.new
order.line_items << LineItem.new(quantity: 2, unit_price: 10_00)
order.line_items.delete_at(0)  # External code mutates the collection
order.line_items = []           # External code replaces the entire collection
order.line_items.clear          # External code empties it
# The Order has no control over its own state
```

```ruby
# AFTER: Encapsulated — Order controls all access
class Order
  def initialize
    @line_items = []
  end

  def add_item(product:, quantity:)
    raise ArgumentError, "Quantity must be positive" unless quantity > 0

    existing = @line_items.find { |li| li.product == product }
    if existing
      existing.quantity += quantity
    else
      @line_items << LineItem.new(product: product, quantity: quantity, unit_price: product.price)
    end
  end

  def remove_item(product)
    @line_items.reject! { |li| li.product == product }
  end

  def line_items
    @line_items.dup.freeze  # Return a frozen copy — mutations don't affect the original
  end

  def item_count
    @line_items.sum(&:quantity)
  end

  def empty?
    @line_items.empty?
  end

  def total
    @line_items.sum { |li| li.quantity * li.unit_price }
  end
end

order = Order.new
order.add_item(product: widget, quantity: 2)   # Controlled: validates, merges duplicates
order.remove_item(widget)                       # Controlled: uses Order's own method
order.line_items                                # Returns frozen copy — can read but not mutate
order.line_items << something                   # FrozenError — can't modify the copy
```

## Why This Is Good

- **Invariants are enforced.** `add_item` validates quantity, merges duplicates, and sets unit price from the product. Raw `<<` skips all of this.
- **Change notification is possible.** If `add_item` needs to recalculate totals, trigger events, or update caches, it can. Raw mutation bypasses all hooks.
- **The collection can't be replaced.** No `order.line_items = []` wiping the data. The only way to modify is through the Order's intentional interface.
- **Frozen copies enable safe reads.** Callers can iterate, map, and filter the returned collection without accidentally modifying the Order's state.

## When To Apply

- **Any class that owns a collection.** If a class has an `attr_accessor` or `attr_reader` for an Array or Hash, encapsulate it.
- **When the collection has rules.** No duplicates, maximum size, items must be valid, items must belong to the parent — these rules belong in the owning class, not scattered across callers.
- **Domain objects and value objects.** `Cart`, `Order`, `Playlist`, `Team` — anything with a "contains items" relationship.

## When NOT To Apply

- **ActiveRecord associations.** `has_many :line_items` is already encapsulated by Rails with callbacks, validations, and scoping. Don't wrap it in another layer.
- **Simple data transfer objects.** A Struct or Data class that just carries data doesn't need encapsulation — it's intentionally transparent.
- **Internal implementation details.** If the collection is only used inside the class and never exposed, encapsulation isn't needed.

## Edge Cases

**Exposing an iterator instead of the collection:**

```ruby
def each_item(&block)
  @line_items.each(&block)
end
include Enumerable  # Now Order is iterable but the array isn't exposed
```

**Hash encapsulation:**

```ruby
class Configuration
  def initialize
    @settings = {}
  end

  def set(key, value)
    @settings[key.to_sym] = value
  end

  def get(key, default: nil)
    @settings.fetch(key.to_sym, default)
  end

  def to_h
    @settings.dup.freeze
  end
end
```
