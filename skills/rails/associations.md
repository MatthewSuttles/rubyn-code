# Rails: ActiveRecord Associations

## Pattern

Define associations explicitly with appropriate options. Always set `dependent` on `has_many`. Use `inverse_of` when Rails can't infer it. Prefer `has_many :through` over `has_and_belongs_to_many`. Use `counter_cache` to avoid N+1 counts.

```ruby
class User < ApplicationRecord
  has_many :orders, dependent: :destroy, inverse_of: :user
  has_many :line_items, through: :orders
  has_many :reviews, dependent: :destroy
  has_many :project_memberships, dependent: :destroy
  has_many :projects, through: :project_memberships
  has_one :profile, dependent: :destroy

  # Optional belongs_to (Rails 5+ requires belongs_to by default)
  belongs_to :company, optional: true
end

class Order < ApplicationRecord
  belongs_to :user, counter_cache: true
  has_many :line_items, dependent: :destroy, inverse_of: :order
  has_one :shipment, dependent: :destroy

  # Scoped association
  has_many :active_line_items, -> { where(cancelled: false) },
           class_name: "LineItem",
           inverse_of: :order
end

class LineItem < ApplicationRecord
  belongs_to :order, counter_cache: true
  belongs_to :product

  # Validate presence of the association, not just the foreign key
  validates :order, presence: true
  validates :product, presence: true
end
```

`has_many :through` for many-to-many with join model:

```ruby
class Project < ApplicationRecord
  has_many :project_memberships, dependent: :destroy
  has_many :users, through: :project_memberships
end

class ProjectMembership < ApplicationRecord
  belongs_to :project
  belongs_to :user

  enum :role, { owner: 0, admin: 1, member: 2, viewer: 3 }

  validates :project_id, uniqueness: { scope: :user_id }
end

class User < ApplicationRecord
  has_many :project_memberships, dependent: :destroy
  has_many :projects, through: :project_memberships

  def role_in(project)
    project_memberships.find_by(project: project)&.role
  end

  def member_of?(project)
    project_memberships.exists?(project: project)
  end
end
```

## Why This Is Good

- **`dependent: :destroy` prevents orphans.** When a user is deleted, their orders are destroyed too. Without this, you get orphaned records with foreign keys pointing to nothing.
- **`inverse_of` optimizes memory.** Rails reuses the same object in memory instead of loading a new one. `order.user` and `user.orders.first.user` return the same object instance, saving queries and preventing stale data.
- **`counter_cache` eliminates count queries.** `user.orders_count` reads a column instead of running `SELECT COUNT(*)`. For pages that display counts for many records, this prevents N+1 count queries.
- **`has_many :through` gives you a join model.** The join model can have its own attributes (role, permissions, created_at), validations, and callbacks. `has_and_belongs_to_many` can't.
- **Scoped associations provide named, preloadable subsets.** `order.active_line_items` is preloadable with `includes(:active_line_items)` and reads clearly.

## Anti-Pattern

Missing dependent options, using HABTM, and ignoring inverse_of:

```ruby
class User < ApplicationRecord
  # BAD: No dependent — deleting a user orphans all their orders
  has_many :orders

  # BAD: HABTM — no join model, can't add attributes or validations
  has_and_belongs_to_many :projects
end

class Order < ApplicationRecord
  # BAD: belongs_to without counter_cache when counts are displayed frequently
  belongs_to :user

  # BAD: No dependent — deleting an order orphans line items
  has_many :line_items

  # BAD: Accessing association in a way that breaks inverse_of
  has_many :items, class_name: "LineItem", foreign_key: "order_id"
  # Rails can't infer inverse_of for :items because the name doesn't match
end
```

## Why This Is Bad

- **Missing `dependent` creates orphaned records.** `User.destroy` leaves behind orders, line items, and shipments with `user_id` pointing to a deleted record. Foreign key constraints fail or, worse, the data silently rots.
- **HABTM can't have join attributes.** You can't store when a user joined a project, what role they have, or who invited them. You're stuck with just the two foreign keys. Every non-trivial many-to-many needs a join model eventually — start with `has_many :through`.
- **Missing `inverse_of` causes extra queries.** Without it, `order.line_items.first.order` loads the order again from the database instead of reusing the object already in memory. In loops, this multiplies into hundreds of unnecessary queries.
- **Missing `counter_cache` on frequently counted associations.** If your UI shows "12 orders" next to every user, that's a COUNT query per user. With 50 users on the page, that's 50 COUNT queries.

## When To Apply

- **Always set `dependent` on `has_many` and `has_one`.** Choose:
  - `:destroy` — run callbacks on each child (use when children have their own dependents or callbacks)
  - `:delete_all` — single DELETE SQL, skip callbacks (faster, use when children have no dependents)
  - `:nullify` — set foreign key to NULL (use when the child can exist without the parent)
  - `:restrict_with_error` — prevent deletion if children exist (use for referential integrity)

- **Always use `has_many :through`** for many-to-many. Even if you don't need join attributes today, you will tomorrow.

- **Set `inverse_of`** when the association name doesn't match the class name, or when using `:foreign_key`, `:class_name`, or scoped associations.

- **Use `counter_cache`** when you display counts in lists (index pages, admin panels, dashboards).

## When NOT To Apply

- **Don't add `dependent: :destroy` on `belongs_to`.** Destroying a line item should not destroy the order it belongs to. Dependent options go on the "parent" side (`has_many`/`has_one`).
- **Don't over-use `counter_cache`.** It adds a write on every insert/delete of the child. If counts are only viewed in admin reports (not on every page load), a query is fine.
- **Don't create associations you don't need.** If `User` never needs to directly access `LineItem` without going through `Order`, don't add `has_many :line_items, through: :orders` unless you have a concrete use case.

## Edge Cases

**Polymorphic associations:**
Use when multiple models can be the parent:

```ruby
class Comment < ApplicationRecord
  belongs_to :commentable, polymorphic: true
end

class Order < ApplicationRecord
  has_many :comments, as: :commentable, dependent: :destroy
end

class Product < ApplicationRecord
  has_many :comments, as: :commentable, dependent: :destroy
end
```

Downside: polymorphic foreign keys can't have database-level foreign key constraints. Use application-level validations.

**Self-referential associations:**

```ruby
class Employee < ApplicationRecord
  belongs_to :manager, class_name: "Employee", optional: true, inverse_of: :direct_reports
  has_many :direct_reports, class_name: "Employee", foreign_key: :manager_id,
           dependent: :nullify, inverse_of: :manager
end
```

**`touch: true` for cache invalidation:**

```ruby
class LineItem < ApplicationRecord
  belongs_to :order, touch: true  # Updates order.updated_at when line item changes
end
```

This is essential for Russian doll caching — changing a line item invalidates the order's cache fragment automatically.

**Preloading polymorphic associations:**

```ruby
# Must specify each possible type
Comment.includes(:commentable)  # Works but may generate N queries for N types

# Better: preload specific types
comments = Comment.where(commentable_type: "Order").includes(:commentable)
```
