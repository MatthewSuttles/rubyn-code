# RSpec: System Specs (Capybara)

## Pattern

System specs drive a real browser to test complete user journeys — clicking, filling forms, seeing results. They're the most expensive specs but provide the highest confidence that the feature works end-to-end. Write them for critical paths, not every edge case.

```ruby
# spec/system/order_checkout_spec.rb
require "rails_helper"

RSpec.describe "Order checkout", type: :system do
  let(:user) { create(:user) }
  let!(:product) { create(:product, name: "Widget", price: 25_00, stock: 10) }

  before do
    driven_by(:selenium_chrome_headless)
    sign_in user
  end

  it "completes a full checkout flow" do
    # Browse products
    visit products_path
    expect(page).to have_content("Widget")
    expect(page).to have_content("$25.00")

    # Add to cart
    within "#product_#{product.id}" do
      click_button "Add to Cart"
    end
    expect(page).to have_content("Added to cart")

    # View cart and proceed
    visit cart_path
    expect(page).to have_content("Widget")
    fill_in "Quantity", with: "2"
    click_button "Update"
    expect(page).to have_content("$50.00")

    # Checkout
    click_link "Checkout"
    fill_in "Shipping address", with: "123 Main St, Austin, TX 78701"
    click_button "Place Order"

    # Confirmation
    expect(page).to have_content("Order placed")
    expect(page).to have_content("ORD-")
    expect(page).to have_content("$50.00")
    expect(page).to have_content("123 Main St")
  end

  it "shows validation errors for incomplete checkout" do
    visit new_order_path
    click_button "Place Order"

    expect(page).to have_content("Shipping address can't be blank")
    expect(page).to have_selector(".field_with_errors")
  end

  it "prevents checkout when product is out of stock" do
    product.update!(stock: 0)
    visit product_path(product)

    expect(page).to have_content("Out of Stock")
    expect(page).not_to have_button("Add to Cart")
  end
end
```

### Testing JavaScript Interactions

```ruby
RSpec.describe "Order management", type: :system do
  before do
    driven_by(:selenium_chrome_headless)
    sign_in create(:user, :admin)
  end

  it "filters orders with live search" do
    create(:order, reference: "ORD-001", status: :pending)
    create(:order, reference: "ORD-002", status: :shipped)

    visit admin_orders_path

    # Turbo Frame search — updates without page reload
    fill_in "Search", with: "ORD-001"

    # Capybara auto-waits for the DOM to update
    expect(page).to have_content("ORD-001")
    expect(page).not_to have_content("ORD-002")
  end

  it "toggles order details inline" do
    order = create(:order, :with_line_items)
    visit admin_orders_path

    # Click to expand details (Stimulus controller)
    within "#order_#{order.id}" do
      click_button "Details"
      expect(page).to have_content(order.line_items.first.product.name)

      # Click again to collapse
      click_button "Details"
      expect(page).not_to have_content(order.line_items.first.product.name)
    end
  end

  it "handles confirmation dialogs" do
    order = create(:order, :pending)
    visit admin_order_path(order)

    accept_confirm "Are you sure you want to cancel this order?" do
      click_button "Cancel Order"
    end

    expect(page).to have_content("Order cancelled")
    expect(page).to have_content("Cancelled")
  end

  it "handles dismiss of confirmation" do
    order = create(:order, :pending)
    visit admin_order_path(order)

    dismiss_confirm do
      click_button "Cancel Order"
    end

    expect(page).to have_content("Pending")  # Status unchanged
  end
end
```

### Testing Authentication Flows

```ruby
RSpec.describe "Authentication", type: :system do
  before { driven_by(:selenium_chrome_headless) }

  it "signs in with valid credentials" do
    user = create(:user, email: "alice@example.com", password: "securepassword")

    visit new_user_session_path
    fill_in "Email", with: "alice@example.com"
    fill_in "Password", with: "securepassword"
    click_button "Sign In"

    expect(page).to have_content("Signed in successfully")
    expect(page).to have_content("alice@example.com")
  end

  it "rejects invalid credentials" do
    create(:user, email: "alice@example.com", password: "securepassword")

    visit new_user_session_path
    fill_in "Email", with: "alice@example.com"
    fill_in "Password", with: "wrongpassword"
    click_button "Sign In"

    expect(page).to have_content("Invalid Email or password")
    expect(page).to have_current_path(new_user_session_path)
  end

  it "redirects unauthenticated users to sign in" do
    visit orders_path

    expect(page).to have_current_path(new_user_session_path)
    expect(page).to have_content("You need to sign in")
  end
end
```

### Setup and Configuration

```ruby
# spec/rails_helper.rb (relevant additions)
RSpec.configure do |config|
  # System test configuration
  config.before(:each, type: :system) do
    driven_by :selenium_chrome_headless
  end

  # Use visible Chrome for debugging (override in specific tests)
  # driven_by :selenium, using: :chrome, screen_size: [1400, 900]
end
```

```ruby
# spec/support/system_helpers.rb
module SystemHelpers
  def sign_in(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"  # Assumes factory default
    click_button "Sign In"
    expect(page).to have_content("Signed in")
  end

  def sign_out
    click_link "Sign Out"
  end
end

RSpec.configure do |config|
  config.include SystemHelpers, type: :system
end
```

### Capybara Matchers Cheat Sheet

```ruby
# Content assertions
expect(page).to have_content("text")           # Anywhere on page
expect(page).not_to have_content("text")
expect(page).to have_selector("h1", text: "Orders")  # CSS + text
expect(page).to have_selector(".badge", count: 3)     # Exact count

# Form assertions
expect(page).to have_field("Email", with: "alice@example.com")
expect(page).to have_checked_field("Remember me")
expect(page).to have_select("Status", selected: "Pending")
expect(page).to have_button("Submit")
expect(page).to have_link("Edit")

# Scoping
within "#order-form" do
  fill_in "Address", with: "123 Main"
  click_button "Save"
end

within_table "orders" do
  expect(page).to have_content("ORD-001")
end

# Waiting (Capybara auto-waits by default, up to Capybara.default_max_wait_time)
expect(page).to have_content("Loading complete")           # Waits automatically
expect(page).to have_selector(".result", wait: 10)         # Custom wait time
expect(page).to have_no_content("Loading...", wait: 5)     # Wait for disappearance

# Navigation
expect(page).to have_current_path(orders_path)
expect(page).to have_current_path(/orders\/\d+/)  # Regex match

# JavaScript
page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
accept_alert { click_link "Dangerous" }
accept_confirm { click_button "Delete" }
dismiss_confirm { click_button "Delete" }
```

## Why This Is Good

- **Tests what users actually experience.** Click a button, fill a form, see a result. If this test passes, the feature works.
- **Catches integration bugs.** Broken JavaScript, missing CSRF tokens, Turbo Frame issues, CSS hiding elements — system specs catch what unit tests miss.
- **Capybara auto-waits.** `have_content` waits for text to appear (for async rendering, Turbo updates). No manual `sleep` calls for most cases.
- **`driven_by :selenium_chrome_headless`** runs fast without a visible browser window.

## Anti-Pattern

```ruby
# BAD: Testing model logic in a system spec
it "validates email format" do
  visit signup_path
  fill_in "Email", with: "invalid"
  click_button "Sign Up"
  expect(page).to have_content("Email is invalid")
end
# This takes 2-3 seconds. A model spec does it in 2ms:
# expect(User.new(email: "invalid")).not_to be_valid

# BAD: Testing every edge case in system specs
# 15 system specs for form validation ← TOO MANY
# 1 system spec for happy path + 14 model specs for validations ← RIGHT
```

## When To Apply

- **Critical user journeys.** Sign up, sign in, checkout, key CRUD flows — 1 system spec per journey.
- **JavaScript-dependent features.** Turbo Frames, Stimulus controllers, live search, modals, drag-and-drop.
- **Smoke tests.** One test per major page to verify it loads without errors.
- **Keep count low.** Target 10-30 system specs for a typical Rails app. Not 200.

## When NOT To Apply

- **Validation logic.** Test in model specs (2ms vs 2s).
- **API endpoints.** Test with request specs — no browser needed.
- **Service object logic.** Test in service specs.
- **Every permutation.** System specs for happy paths. Unit tests for edge cases.
