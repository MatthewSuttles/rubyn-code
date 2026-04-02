# Rails: Internationalization (i18n)

## Pattern

Use Rails i18n for all user-facing text, even in English-only apps. It centralizes copy, supports pluralization, enables future translation, and keeps views clean.

### Basic Setup

```yaml
# config/locales/en.yml
en:
  orders:
    index:
      title: "Your Orders"
      empty: "You haven't placed any orders yet."
      count:
        one: "%{count} order"
        other: "%{count} orders"
    show:
      title: "Order %{reference}"
      status:
        pending: "Awaiting confirmation"
        confirmed: "Processing"
        shipped: "On its way"
        delivered: "Delivered"
        cancelled: "Cancelled"
    create:
      success: "Order placed successfully!"
      failure: "Could not place order. Please check the errors below."
  
  shared:
    actions:
      edit: "Edit"
      delete: "Delete"
      cancel: "Cancel"
      save: "Save Changes"
      back: "Back"
    confirmations:
      delete: "Are you sure? This cannot be undone."
```

### Usage in Views

```erb
<%# Views use t() helper %>
<h1><%= t(".title") %></h1>  <%# Lazy lookup — resolves to orders.index.title %>

<% if @orders.empty? %>
  <p><%= t(".empty") %></p>
<% else %>
  <p><%= t(".count", count: @orders.count) %></p>  <%# Pluralization %>
<% end %>

<%= link_to t("shared.actions.edit"), edit_order_path(@order) %>

<%# Status with translation %>
<span class="badge"><%= t("orders.show.status.#{@order.status}") %></span>
```

### Usage in Controllers

```ruby
class OrdersController < ApplicationController
  def create
    @order = current_user.orders.build(order_params)
    if @order.save
      redirect_to @order, notice: t(".success")
    else
      flash.now[:alert] = t(".failure")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @order.destroy
    redirect_to orders_path, notice: t("orders.destroy.success", reference: @order.reference)
  end
end
```

### Model Validations

```yaml
# config/locales/en.yml
en:
  activerecord:
    errors:
      models:
        order:
          attributes:
            shipping_address:
              blank: "is required for delivery"
            total:
              greater_than: "must be a positive amount"
        user:
          attributes:
            email:
              taken: "is already registered. Did you mean to sign in?"
```

```ruby
# These override Rails' default validation messages automatically
class Order < ApplicationRecord
  validates :shipping_address, presence: true
  # Error message: "Shipping address is required for delivery"
end
```

### Organizing Locale Files

```
config/locales/
├── en.yml                    # Shared/global translations
├── models/
│   ├── en.yml                # ActiveRecord model names and attributes
│   └── errors/
│       └── en.yml            # Validation error messages
├── views/
│   ├── orders.en.yml         # Order view translations
│   ├── users.en.yml          # User view translations
│   └── admin.en.yml          # Admin panel translations
└── mailers/
    └── en.yml                # Email subject lines and content
```

```ruby
# config/application.rb
config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.yml")]
config.i18n.default_locale = :en
config.i18n.fallbacks = true  # Fall back to :en if translation missing
```

### Date and Number Formatting

```yaml
# config/locales/en.yml
en:
  date:
    formats:
      short: "%b %d"          # "Mar 20"
      long: "%B %d, %Y"       # "March 20, 2026"
  time:
    formats:
      short: "%b %d, %I:%M %p"  # "Mar 20, 02:30 PM"
  number:
    currency:
      format:
        unit: "$"
        precision: 2
```

```erb
<%= l(@order.created_at, format: :long) %>   <%# March 20, 2026 %>
<%= l(@order.created_at, format: :short) %>  <%# Mar 20 %>
<%= number_to_currency(@order.total / 100.0) %>  <%# $25.00 %>
```

## Why This Is Good

- **Single source of truth for copy.** Changing "Place Order" to "Complete Purchase" across the entire app means editing one YAML line, not grep-replacing across 15 files.
- **Lazy lookup keeps views clean.** `t(".title")` in `orders/index.html.erb` automatically resolves to `en.orders.index.title`. No long key paths in views.
- **Pluralization is handled.** `t(".count", count: 1)` → "1 order." `t(".count", count: 5)` → "5 orders." Works correctly for languages with complex pluralization rules.
- **Validation messages are customizable per model.** "Email is already registered. Did you mean to sign in?" is more helpful than "Email has already been taken."
- **Future-proofs for translation.** Even if you're English-only today, adding Spanish later means adding `es.yml` files — no code changes.

## Anti-Pattern

```ruby
# BAD: Hardcoded strings in views
<h1>Your Orders</h1>
<p>You have <%= @orders.count %> order<%= @orders.count == 1 ? "" : "s" %></p>

# BAD: Hardcoded strings in controllers
redirect_to @order, notice: "Order placed successfully!"
flash[:alert] = "Something went wrong"

# BAD: Hardcoded validation messages
validates :email, uniqueness: { message: "is already taken" }
# Use locale files instead — they're overridable per model
```

## When To Apply

- **Every user-facing string.** Views, flash messages, mailer subject lines, validation messages, error pages.
- **Even English-only apps.** Centralizing copy in YAML is valuable for consistency and maintainability regardless of language count.
- **Date and number formatting.** Use `l()` for dates and `number_to_currency` for money — they respect locale settings.

## When NOT To Apply

- **Log messages.** Logs are for developers, not users. Log in English, always.
- **Developer-facing text.** Rake task output, console messages, internal error classes. These stay as plain strings.
- **API responses.** JSON APIs typically return machine-readable codes, not translated text. Error codes like `"insufficient_credits"` don't need i18n.
