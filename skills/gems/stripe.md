# Gems: Stripe Integration

## Pattern

Wrap Stripe behind adapters and service objects. Never call Stripe directly from controllers. Handle webhooks idempotently. Use Stripe's test mode and fixtures for development.

### Service Objects for Stripe Operations

```ruby
# app/services/billing/create_subscription_service.rb
module Billing
  class CreateSubscriptionService
    def self.call(user, plan:)
      new(user, plan: plan).call
    end

    def initialize(user, plan:)
      @user = user
      @plan = plan
    end

    def call
      customer = find_or_create_customer
      subscription = Stripe::Subscription.create(
        customer: customer.id,
        items: [{ price: price_id_for(@plan) }],
        payment_behavior: "default_incomplete",
        expand: ["latest_invoice.payment_intent"]
      )

      @user.update!(
        stripe_customer_id: customer.id,
        stripe_subscription_id: subscription.id,
        plan: @plan
      )

      Result.new(success: true, subscription: subscription)
    rescue Stripe::CardError => e
      Result.new(success: false, error: "Payment failed: #{e.message}")
    rescue Stripe::InvalidRequestError => e
      Rails.logger.error("Stripe error: #{e.message}")
      Result.new(success: false, error: "Unable to process. Please try again.")
    end

    private

    def find_or_create_customer
      if @user.stripe_customer_id.present?
        Stripe::Customer.retrieve(@user.stripe_customer_id)
      else
        Stripe::Customer.create(email: @user.email, name: @user.name)
      end
    end

    def price_id_for(plan)
      {
        "pro" => ENV.fetch("STRIPE_PRO_PRICE_ID"),
        "team" => ENV.fetch("STRIPE_TEAM_PRICE_ID")
      }.fetch(plan)
    end
  end
end
```

### Webhook Handler

```ruby
# app/controllers/webhooks/stripe_controller.rb
class Webhooks::StripeController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!

  def create
    payload = request.body.read
    sig_header = request.env["HTTP_STRIPE_SIGNATURE"]

    begin
      event = Stripe::Webhook.construct_event(
        payload, sig_header, ENV.fetch("STRIPE_WEBHOOK_SECRET")
      )
    rescue JSON::ParserError, Stripe::SignatureVerificationError
      head :bad_request
      return
    end

    # Dispatch to handler — idempotently
    Webhooks::StripeDispatcher.call(event)

    head :ok
  end
end

# app/services/webhooks/stripe_dispatcher.rb
module Webhooks
  class StripeDispatcher
    HANDLERS = {
      "checkout.session.completed" => Webhooks::Stripe::CheckoutCompleted,
      "invoice.payment_succeeded" => Webhooks::Stripe::InvoicePaymentSucceeded,
      "invoice.payment_failed" => Webhooks::Stripe::InvoicePaymentFailed,
      "customer.subscription.updated" => Webhooks::Stripe::SubscriptionUpdated,
      "customer.subscription.deleted" => Webhooks::Stripe::SubscriptionDeleted,
    }.freeze

    def self.call(event)
      handler = HANDLERS[event.type]

      if handler
        handler.call(event)
      else
        Rails.logger.info("Unhandled Stripe webhook: #{event.type}")
      end
    end
  end
end

# app/services/webhooks/stripe/invoice_payment_succeeded.rb
module Webhooks
  module Stripe
    class InvoicePaymentSucceeded
      def self.call(event)
        invoice = event.data.object
        customer_id = invoice.customer

        user = User.find_by(stripe_customer_id: customer_id)
        return unless user  # Idempotent — unknown customer is a no-op

        # Idempotent — check if we already processed this invoice
        return if user.credit_ledger_entries.exists?(stripe_invoice_id: invoice.id)

        Credits::GrantService.call(
          user: user,
          amount: credits_for_plan(user.plan),
          source: :subscription_grant,
          description: "Monthly credit grant",
          stripe_invoice_id: invoice.id
        )
      end

      private_class_method def self.credits_for_plan(plan)
        { "pro" => 1000, "team" => 5000 }.fetch(plan, 0)
      end
    end
  end
end
```

### Testing Stripe

```ruby
# spec/services/billing/create_subscription_service_spec.rb
RSpec.describe Billing::CreateSubscriptionService do
  let(:user) { create(:user, email: "alice@example.com") }

  before do
    # Stub Stripe API calls
    stub_request(:post, "https://api.stripe.com/v1/customers")
      .to_return(status: 200, body: { id: "cus_test123", email: "alice@example.com" }.to_json)

    stub_request(:post, "https://api.stripe.com/v1/subscriptions")
      .to_return(status: 200, body: {
        id: "sub_test456",
        status: "active",
        latest_invoice: { payment_intent: { client_secret: "pi_secret" } }
      }.to_json)
  end

  it "creates a subscription and updates user" do
    result = described_class.call(user, plan: "pro")

    expect(result).to be_success
    expect(user.reload.stripe_customer_id).to eq("cus_test123")
    expect(user.plan).to eq("pro")
  end
end

# spec/requests/webhooks/stripe_spec.rb
RSpec.describe "Stripe Webhooks", type: :request do
  let(:payload) { { type: "invoice.payment_succeeded", data: { object: { customer: "cus_123", id: "inv_456" } } }.to_json }

  before do
    allow(Stripe::Webhook).to receive(:construct_event).and_return(
      Stripe::Event.construct_from(JSON.parse(payload))
    )
  end

  it "returns 200 and processes the event" do
    user = create(:user, stripe_customer_id: "cus_123", plan: "pro")

    post webhooks_stripe_path, params: payload, headers: { "Stripe-Signature" => "sig" }

    expect(response).to have_http_status(:ok)
    expect(user.credit_ledger_entries.count).to eq(1)
  end

  it "returns 200 for unknown event types" do
    payload = { type: "unknown.event" }.to_json
    allow(Stripe::Webhook).to receive(:construct_event).and_return(
      Stripe::Event.construct_from(JSON.parse(payload))
    )

    post webhooks_stripe_path, params: payload, headers: { "Stripe-Signature" => "sig" }

    expect(response).to have_http_status(:ok)
  end
end
```

## Why This Is Good

- **Service objects wrap Stripe calls.** Controllers stay thin. Stripe-specific error handling is centralized.
- **Webhook handlers are idempotent.** Stripe may send the same event multiple times. Checking for existing `stripe_invoice_id` prevents double-granting credits.
- **Dispatcher pattern for webhooks.** New event types get a new handler class — existing handlers are untouched. Open/Closed principle.
- **Signature verification prevents spoofing.** `construct_event` validates the webhook payload against Stripe's secret.
- **WebMock for testing.** No real Stripe calls in tests. Stubbed responses are fast, deterministic, and free.

## When To Apply

- **Every Stripe integration.** Always use service objects, always verify webhook signatures, always handle idempotently.
- **Credit systems.** Webhook-driven credit grants ensure credits are added when payment actually succeeds, not when the user clicks "subscribe."

## When NOT To Apply

- **Don't use Stripe Checkout for simple one-time charges.** Stripe Payment Links or a simple `Stripe::Charge.create` might be simpler for MVP.
- **Don't build your own billing UI if Stripe's Customer Portal works.** Let Stripe handle plan changes, payment method updates, and invoice history.
