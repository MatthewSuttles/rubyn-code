# Rails: Mailers

## Pattern

Mailers are the email equivalent of controllers — thin orchestrators that set up data and pick a template. Keep them simple, always deliver asynchronously, use previews for development, and test the envelope (to, from, subject) separately from the content.

```ruby
# app/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: "Rubyn <noreply@rubyn.ai>"
  layout "mailer"
end

# app/mailers/order_mailer.rb
class OrderMailer < ApplicationMailer
  def confirmation(order)
    @order = order
    @user = order.user

    mail(
      to: @user.email,
      subject: "Order #{@order.reference} Confirmed"
    )
  end

  def shipped(order)
    @order = order
    @user = order.user
    @tracking_url = tracking_url(@order.tracking_number)

    mail(
      to: @user.email,
      subject: "Your order has shipped!"
    )
  end

  def receipt(order)
    @order = order.includes(:line_items)
    @user = order.user

    attachments["receipt-#{@order.reference}.pdf"] = Orders::ReceiptPdfService.call(@order)

    mail(
      to: @user.email,
      subject: "Receipt for Order #{@order.reference}"
    )
  end

  private

  def tracking_url(number)
    "https://tracking.example.com/#{number}"
  end
end
```

### Always Deliver Asynchronously

```ruby
# GOOD: deliver_later — enqueues to Active Job (Sidekiq/etc)
OrderMailer.confirmation(order).deliver_later

# GOOD: deliver_later with delay
OrderMailer.review_reminder(order).deliver_later(wait: 7.days)

# BAD: deliver_now blocks the request
OrderMailer.confirmation(order).deliver_now
# User waits 1-3 seconds for SMTP handshake — terrible UX

# EXCEPTION: deliver_now is fine inside a background job
class OrderConfirmationJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    OrderMailer.confirmation(order).deliver_now  # Already async — job handles the retry
  end
end
```

### Mailer Previews

```ruby
# test/mailers/previews/order_mailer_preview.rb (or spec/mailers/previews/)
class OrderMailerPreview < ActionMailer::Preview
  def confirmation
    order = Order.first || FactoryBot.create(:order)
    OrderMailer.confirmation(order)
  end

  def shipped
    order = Order.shipped.first || FactoryBot.create(:order, :shipped, tracking_number: "1Z999AA10123456784")
    OrderMailer.shipped(order)
  end

  def receipt
    order = Order.includes(:line_items).first || FactoryBot.create(:order, :with_line_items)
    OrderMailer.receipt(order)
  end
end

# Visit http://localhost:3000/rails/mailers to see rendered previews
# No actual email sent — just renders the template in the browser
```

### Views

```erb
<%# app/views/order_mailer/confirmation.html.erb %>
<h1>Order Confirmed!</h1>
<p>Hi <%= @user.name %>,</p>
<p>Your order <strong><%= @order.reference %></strong> has been confirmed.</p>

<table>
  <% @order.line_items.each do |item| %>
    <tr>
      <td><%= item.product.name %></td>
      <td><%= item.quantity %></td>
      <td>$<%= format("%.2f", item.unit_price / 100.0) %></td>
    </tr>
  <% end %>
</table>

<p><strong>Total: $<%= format("%.2f", @order.total / 100.0) %></strong></p>
<p>Shipping to: <%= @order.shipping_address %></p>

<%= link_to "View Order", order_url(@order) %>
```

```erb
<%# app/views/order_mailer/confirmation.text.erb — always provide a text version %>
Order Confirmed!

Hi <%= @user.name %>,

Your order <%= @order.reference %> has been confirmed.

<% @order.line_items.each do |item| %>
- <%= item.product.name %> x<%= item.quantity %> — $<%= format("%.2f", item.unit_price / 100.0) %>
<% end %>

Total: $<%= format("%.2f", @order.total / 100.0) %>
Shipping to: <%= @order.shipping_address %>

View your order: <%= order_url(@order) %>
```

## Why This Is Good

- **Thin mailers.** The mailer sets instance variables and calls `mail()`. No business logic, no formatting, no conditionals beyond what's needed for the template.
- **`deliver_later` is non-blocking.** The user's request completes instantly. The email sends in a background job with automatic retries.
- **Previews catch visual bugs.** See the rendered email in your browser without sending it. Catch broken layouts, missing data, and formatting issues before they reach users.
- **Text + HTML versions.** Email clients that don't render HTML (or users who prefer plain text) get a readable version. Also improves spam score.
- **Attachments via service objects.** PDF generation is delegated to a service, not done inline in the mailer.

## Anti-Pattern

```ruby
# BAD: Business logic in the mailer
class OrderMailer < ApplicationMailer
  def confirmation(order)
    @order = order
    @user = order.user
    @discount = order.total > 100_00 ? "Use code SAVE10 for 10% off!" : nil
    @recommendations = Product.where.not(id: order.line_items.pluck(:product_id)).limit(3)
    @user.update!(last_emailed_at: Time.current)  # Side effect in a mailer!
    mail(to: @user.email, subject: "Order Confirmed")
  end
end
```

## When To Apply

- **Every email.** Use mailers for all outgoing email, even simple ones. Direct `Mail.deliver` bypasses Rails' template rendering, previews, and testing infrastructure.
- **`deliver_later` always.** The only exception is inside a background job that's already async.
- **Previews for every mailer.** Set them up once, save hours of "send test email, check inbox, repeat."
- **Both HTML and text templates.** Plain text is required for accessibility and deliverability.

## When NOT To Apply

- **Transactional SMS or push notifications.** These aren't emails — use dedicated services, not ActionMailer.
- **Don't put conditional sending logic in the mailer.** "Don't send if user has unsubscribed" belongs in the service that calls the mailer, not in the mailer itself.
