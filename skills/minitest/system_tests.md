# Minitest: System Tests (Capybara)

## Pattern

System tests drive a real browser to test full user journeys — clicking links, filling forms, asserting visible content. They're the most expensive tests but provide the highest confidence that the app works end-to-end.

```ruby
# test/system/orders_test.rb
require "application_system_test_case"

class OrdersTest < ApplicationSystemTestCase
  setup do
    @user = users(:alice)
    sign_in_as @user
  end

  test "viewing the orders list" do
    visit orders_path

    assert_text "Your Orders"
    assert_text orders(:pending_order).reference
  end

  test "creating a new order" do
    visit new_order_path

    fill_in "Shipping address", with: "789 Elm St, Austin, TX"
    select "Widget", from: "Product"
    fill_in "Quantity", with: "3"

    click_button "Place Order"

    assert_text "Order placed"
    assert_text "789 Elm St"
    assert_text "Widget"
  end

  test "editing an existing order" do
    visit order_path(orders(:pending_order))

    click_link "Edit"

    fill_in "Shipping address", with: "Updated Address"
    click_button "Save"

    assert_text "Updated"
    assert_text "Updated Address"
  end

  test "cancelling an order" do
    visit order_path(orders(:pending_order))

    accept_confirm "Are you sure?" do
      click_button "Cancel Order"
    end

    assert_text "Order cancelled"
    assert_text "Cancelled"
  end

  test "searching orders" do
    visit orders_path

    fill_in "Search", with: orders(:pending_order).reference
    click_button "Search"

    assert_text orders(:pending_order).reference
    assert_no_text orders(:shipped_order).reference
  end

  test "pagination" do
    # Create enough orders to trigger pagination
    30.times { |i| Order.create!(user: @user, reference: "ORD-#{i}", shipping_address: "Test", status: :pending, total: 10_00) }

    visit orders_path

    assert_selector ".order-row", count: 25  # First page
    click_link "Next"
    assert_selector ".order-row"  # Second page has remaining orders
  end

  private

  def sign_in_as(user)
    visit login_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "password"
    click_button "Sign In"
    assert_text "Signed in"
  end
end
```

### Setup

```ruby
# test/application_system_test_case.rb
require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Headless Chrome — fast, no browser window pops up
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 900]

  # Use visible Chrome for debugging
  # driven_by :selenium, using: :chrome, screen_size: [1400, 900]

  def take_debug_screenshot
    take_screenshot  # Saves to tmp/screenshots/
  end
end
```

### Testing Turbo/Hotwire Interactions

```ruby
class TurboOrdersTest < ApplicationSystemTestCase
  setup do
    sign_in_as users(:alice)
  end

  test "inline editing with Turbo Frames" do
    visit orders_path

    within "##{dom_id(orders(:pending_order))}" do
      click_link "Edit"

      # The form appears INSIDE the frame (no page navigation)
      fill_in "Shipping address", with: "New Address"
      click_button "Save"
    end

    # The frame updates in-place
    assert_text "New Address"
    assert_no_selector "form"  # Form is gone, replaced with display
  end

  test "live search with debounce" do
    visit orders_path

    fill_in "Search", with: orders(:pending_order).reference

    # Wait for Turbo Frame to update (debounced search)
    assert_text orders(:pending_order).reference
    assert_no_text orders(:shipped_order).reference
  end

  test "flash messages appear and dismiss" do
    visit new_order_path
    fill_in "Shipping address", with: "123 Main St"
    click_button "Place Order"

    assert_text "Order placed"

    # Flash auto-dismisses after a few seconds (Stimulus controller)
    sleep 4
    assert_no_text "Order placed"
  end
end
```

### Capybara Matchers Cheat Sheet

```ruby
# Finding elements
assert_text "Expected text"                          # Anywhere on page
assert_no_text "Should not appear"
assert_selector "h1", text: "Orders"                 # CSS selector with text
assert_selector ".order-row", count: 5               # Exact count
assert_selector "#order_123"                         # By ID
assert_link "Edit"                                   # Link text
assert_button "Submit"                               # Button text
assert_field "Email", with: "alice@example.com"      # Input with value

# Scoping
within "#order-form" do
  fill_in "Address", with: "123 Main"
  click_button "Save"
end

within_table "orders" do
  assert_text "ORD-001"
end

# Waiting (Capybara auto-waits by default)
assert_text "Loading complete"  # Waits up to Capybara.default_max_wait_time

# Force wait for async operations
assert_selector ".result", wait: 10  # Wait up to 10 seconds

# JavaScript interactions
accept_confirm { click_button "Delete" }
dismiss_confirm { click_button "Delete" }
accept_alert { click_link "Dangerous action" }

page.execute_script("window.scrollTo(0, document.body.scrollHeight)")
```

## Why This Is Good

- **Tests what users see.** "Fill in email, click sign in, see dashboard" — this is the user's actual experience. If this test passes, the feature works.
- **Catches integration bugs.** JavaScript errors, broken Turbo Frames, missing CSRF tokens, CSS hiding elements — system tests catch what unit tests miss.
- **Capybara auto-waits.** `assert_text` waits for the text to appear (up to the max wait time). No manual `sleep` needed for most async operations.

## Anti-Pattern

Too many system tests or testing logic that belongs in unit tests:

```ruby
# BAD: Testing validation messages in a system test
test "shows error for blank email" do
  visit registration_path
  fill_in "Email", with: ""
  click_button "Sign Up"
  assert_text "Email can't be blank"
end
# This takes 2-3 seconds. A model test takes 2ms.
```

## When To Apply

- **Critical user journeys only.** Sign up, sign in, checkout, key CRUD flows. 10-20 system tests, not 200.
- **JavaScript-dependent features.** Turbo Frames, Stimulus controllers, live search, modals.
- **Smoke tests.** One test per major page to verify it loads without errors.

## When NOT To Apply

- **Validation logic.** Test in model specs (milliseconds vs seconds).
- **API endpoints.** Test with integration tests — no browser needed.
- **Every edge case.** System tests for happy paths, unit tests for edge cases.
- **CI with limited resources.** System tests are 10-100x slower. Keep the count low.

## Speed Tips

- Use `headless_chrome` (no GUI overhead)
- Minimize `sleep` calls — rely on Capybara's auto-waiting
- Share login state across tests in the same class (use `setup`)
- Keep system test count under 50 for fast CI
