# Minitest: Testing Mailers and Background Jobs

## Pattern

Test mailers and jobs as first-class citizens. Mailer tests verify the email content and recipients. Job tests verify the job logic in isolation. Integration tests verify that actions enqueue the right jobs and emails.

### Testing Mailers

```ruby
# test/mailers/order_mailer_test.rb
require "test_helper"

class OrderMailerTest < ActionMailer::TestCase
  test "confirmation email" do
    order = orders(:pending_order)
    email = OrderMailer.confirmation(order)

    # Verify envelope
    assert_equal ["noreply@rubyn.ai"], email.from
    assert_equal [order.user.email], email.to
    assert_equal "Order #{order.reference} Confirmed", email.subject

    # Verify body content
    assert_match order.reference, email.body.encoded
    assert_match "$#{format('%.2f', order.total / 100.0)}", email.body.encoded
    assert_match order.shipping_address, email.body.encoded
  end

  test "shipped email includes tracking" do
    order = orders(:shipped_order)
    order.update!(tracking_number: "1Z999AA10123456784")

    email = OrderMailer.shipped(order)

    assert_equal "Your order has shipped!", email.subject
    assert_match "1Z999AA10123456784", email.body.encoded
  end

  test "does not send to unconfirmed users" do
    user = users(:alice)
    user.update!(confirmed_at: nil)
    order = orders(:pending_order)

    email = OrderMailer.confirmation(order)

    # Mailer returns a null mail object
    assert_nil email.to
  end
end
```

### Testing Background Jobs

```ruby
# test/jobs/order_confirmation_job_test.rb
require "test_helper"

class OrderConfirmationJobTest < ActiveJob::TestCase
  test "sends confirmation email" do
    order = orders(:pending_order)

    assert_emails 1 do
      OrderConfirmationJob.perform_now(order.id)
    end
  end

  test "marks order as confirmation sent" do
    order = orders(:pending_order)
    assert_nil order.confirmation_sent_at

    OrderConfirmationJob.perform_now(order.id)

    assert_not_nil order.reload.confirmation_sent_at
  end

  test "is idempotent — skips if already sent" do
    order = orders(:pending_order)
    order.update!(confirmation_sent_at: 1.hour.ago)

    assert_no_emails do
      OrderConfirmationJob.perform_now(order.id)
    end
  end

  test "handles missing order gracefully" do
    assert_nothing_raised do
      OrderConfirmationJob.perform_now(999_999)
    end
  end
end
```

```ruby
# test/jobs/codebase_index_job_test.rb
require "test_helper"

class CodebaseIndexJobTest < ActiveJob::TestCase
  setup do
    @project = projects(:rubyn_project)
    @fake_embedder = FakeEmbedder.new
  end

  test "creates embeddings for project files" do
    files = { "app/models/order.rb" => "class Order; end" }

    Embeddings::CodebaseIndexer.stub(:new, ->(**) { MockIndexer.new }) do
      assert_difference "@project.code_embeddings.count" do
        CodebaseIndexJob.perform_now(@project.id, files)
      end
    end
  end

  test "updates project indexed_at timestamp" do
    CodebaseIndexJob.perform_now(@project.id, {})

    assert_not_nil @project.reload.last_indexed_at
  end
end
```

### Asserting Jobs are Enqueued

```ruby
# test/controllers/orders_controller_test.rb
class OrdersControllerTest < ActionDispatch::IntegrationTest
  test "create enqueues confirmation job" do
    sign_in users(:alice)

    assert_enqueued_with(job: OrderConfirmationJob) do
      post orders_path, params: { order: valid_params }
    end
  end

  test "create enqueues indexing job" do
    sign_in users(:alice)

    assert_enqueued_with(job: CodebaseIndexJob) do
      post orders_path, params: { order: valid_params }
    end
  end

  test "does not enqueue job on validation failure" do
    sign_in users(:alice)

    assert_no_enqueued_jobs do
      post orders_path, params: { order: { shipping_address: "" } }
    end
  end
end
```

### Testing Job Retries and Error Handling

```ruby
class WebhookDeliveryJobTest < ActiveJob::TestCase
  test "retries on timeout" do
    stub_request(:post, "https://webhook.example.com/hook")
      .to_timeout
      .then
      .to_return(status: 200)

    # perform_now doesn't retry — test the logic directly
    webhook = webhooks(:order_created)

    assert_raises Faraday::TimeoutError do
      WebhookDeliveryJob.perform_now(webhook.id)
    end
  end

  test "discards on 4xx client error" do
    stub_request(:post, "https://webhook.example.com/hook")
      .to_return(status: 404)

    webhook = webhooks(:order_created)

    # Job should not raise — it handles 4xx gracefully
    assert_nothing_raised do
      WebhookDeliveryJob.perform_now(webhook.id)
    end

    assert_equal "failed", webhook.reload.status
  end
end
```

### Performing Enqueued Jobs in Tests

```ruby
# When you need to run enqueued jobs as part of a test
class OrderWorkflowTest < ActiveSupport::TestCase
  test "full order workflow with jobs" do
    user = users(:alice)

    # perform_enqueued_jobs runs all jobs enqueued within the block
    perform_enqueued_jobs do
      result = Orders::CreateService.call(valid_params, user)
      assert result.success?
    end

    # After jobs run, verify side effects
    order = Order.last
    assert_not_nil order.confirmation_sent_at
    assert_equal 1, ActionMailer::Base.deliveries.count
  end
end
```

## Job Assertion Cheat Sheet

| Want to check... | Use |
|---|---|
| A specific job was enqueued | `assert_enqueued_with(job: MyJob, args: [...]) { code }` |
| Any job was enqueued | `assert_enqueued_jobs 1 { code }` |
| No jobs were enqueued | `assert_no_enqueued_jobs { code }` |
| An email was sent | `assert_emails 1 { code }` |
| No emails were sent | `assert_no_emails { code }` |
| Run enqueued jobs | `perform_enqueued_jobs { code }` |
| Job runs without error | `assert_nothing_raised { MyJob.perform_now(args) }` |
