# Design Pattern: Composite

## Pattern

Compose objects into tree structures to represent part-whole hierarchies. The Composite pattern lets clients treat individual objects and compositions of objects uniformly — the same interface for a single item and a group of items.

```ruby
# Permission system — individual permissions and permission groups share the same interface

class Permission
  attr_reader :name

  def initialize(name)
    @name = name
  end

  def grants?(action)
    name == action
  end

  def all_permissions
    [name]
  end

  def to_s
    name
  end
end

class PermissionGroup
  attr_reader :name

  def initialize(name)
    @name = name
    @children = []
  end

  def add(permission)
    @children << permission
    self
  end

  def grants?(action)
    @children.any? { |child| child.grants?(action) }
  end

  def all_permissions
    @children.flat_map(&:all_permissions)
  end

  def to_s
    "#{name}: [#{@children.map(&:to_s).join(', ')}]"
  end
end

# Build a permission tree
read_code = Permission.new("code:read")
write_code = Permission.new("code:write")
delete_code = Permission.new("code:delete")

code_admin = PermissionGroup.new("code_admin")
  .add(read_code)
  .add(write_code)
  .add(delete_code)

read_billing = Permission.new("billing:read")
manage_billing = Permission.new("billing:manage")

billing_admin = PermissionGroup.new("billing_admin")
  .add(read_billing)
  .add(manage_billing)

super_admin = PermissionGroup.new("super_admin")
  .add(code_admin)      # Group containing group
  .add(billing_admin)   # Group containing group

# Uniform interface — works the same for single permissions and groups
read_code.grants?("code:read")        # true
code_admin.grants?("code:read")       # true
super_admin.grants?("billing:manage") # true — traverses the tree
super_admin.all_permissions
# => ["code:read", "code:write", "code:delete", "billing:read", "billing:manage"]
```

Rails-practical example — pricing rules:

```ruby
# Single rule and rule groups share the same interface
class Pricing::FlatDiscount
  def initialize(amount)
    @amount = amount
  end

  def apply(price)
    [price - @amount, 0].max
  end
end

class Pricing::PercentDiscount
  def initialize(percent)
    @percent = percent
  end

  def apply(price)
    price * (1 - @percent / 100.0)
  end
end

class Pricing::DiscountChain
  def initialize
    @discounts = []
  end

  def add(discount)
    @discounts << discount
    self
  end

  def apply(price)
    @discounts.reduce(price) { |p, discount| discount.apply(p) }
  end
end

# Compose discounts
holiday_deal = Pricing::DiscountChain.new
  .add(Pricing::PercentDiscount.new(10))   # 10% off first
  .add(Pricing::FlatDiscount.new(5_00))     # Then $5 off

final_price = holiday_deal.apply(100_00)  # $100 → $90 → $85
```

## Why This Is Good

- **Uniform interface.** `grants?("code:read")` works on a single permission, a group, or a tree of groups. The caller never checks types.
- **Recursive composition.** Groups can contain other groups. `super_admin` contains `code_admin` which contains individual permissions. Any depth works.
- **Easy to extend.** New permission types (time-limited, IP-restricted) just implement `grants?` and `all_permissions`. They plug into any group.

## When To Apply

- **Tree structures** — menus, categories, org charts, file systems, permission hierarchies.
- **Part-whole relationships** — a single discount and a chain of discounts, a single validator and a validator pipeline.
- **When clients need to treat single items and collections identically.**

## When NOT To Apply

- **Flat collections.** If items don't nest, use a simple array. Don't build a Composite for a list.
- **When the leaf and composite have very different interfaces.** If a single permission and a permission group need fundamentally different methods, Composite adds forced uniformity.
