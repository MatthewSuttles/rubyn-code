# Rails: Background Jobs (Sidekiq)

## Pattern

Design jobs to be small, idempotent, and retriable. Pass IDs not objects. Set appropriate queues and retry strategies. Use Sidekiq's features (bulk, batches, rate limiting) for complex workflows.

```ruby
# GOOD: Small, idempotent, passes ID
class OrderConfirmationJob < ApplicationJob
  queue_as :default
  retry_on ActiveRecord::RecordNotFound, wait: 5.seconds, attempts: 3

  def perform(order_id)
    order = Order.find(order_id)
    return if order.confirmation_sent?  # Idempotent check

    OrderMailer.confirmation(order).deliver_now
    order.update!(confirmation_sent_at: Time.current)
  end
end

# Enqueue
OrderConfirmationJob.perform_later(order.id)
```

```ruby
# GOOD: Batch processing with find_each
class RecalculateTotalsJob < ApplicationJob
  queue_as :low

  def perform
    Order.where(total: nil).find_each(batch_size: 500) do |order|
      order.update!(total: order.line_items.sum("quantity * unit_price"))
    end
  end
end
```

```ruby
# GOOD: Job with error handling and dead letter
class WebhookDeliveryJob < ApplicationJob
  queue_as :webhooks
  retry_on Faraday::TimeoutError, wait: :polynomially_longer, attempts: 5
  discard_on Faraday::ClientError  # 4xx errors won't succeed on retry

  def perform(webhook_id)
    webhook = Webhook.find(webhook_id)
    response = Faraday.post(webhook.url, webhook.payload.to_json, "Content-Type" => "application/json")

    if response.success?
      webhook.update!(delivered_at: Time.current, status: :delivered)
    else
      webhook.update!(status: :failed, last_error: "HTTP #{response.status}")
      raise Faraday::ServerError, "Webhook failed: #{response.status}"
    end
  end
end
```

Queue configuration:

```yaml
# config/sidekiq.yml
:concurrency: 10
:queues:
  - [critical, 3]    # Payments, auth — 3x priority
  - [default, 2]     # Email, notifications — 2x priority
  - [embeddings, 1]  # Codebase indexing — normal priority
  - [low, 1]         # Reports, cleanup — normal priority
```

## Why This Is Good

- **Pass IDs, not objects.** Serializing an ActiveRecord object into Redis is fragile — the object might change between enqueue and execution. `Order.find(order_id)` always loads the current state.
- **Idempotent jobs are safe to retry.** If the job runs twice (Redis failover, process crash, manual retry), `return if order.confirmation_sent?` prevents sending a duplicate email. The second run is a no-op.
- **`retry_on` with specific exceptions.** Transient errors (timeout, record not found due to replication lag) get retried with backoff. Permanent errors (`discard_on` for client errors) don't waste retries.
- **Queue separation by priority.** Payment processing gets 3x the scheduling weight of report generation. A backlog of reports doesn't delay payment confirmations.
- **`find_each` in batch jobs.** Processing 100,000 orders loads 500 at a time, not all at once. Memory stays flat.

## Anti-Pattern

Passing objects, doing too much in one job, no idempotency, no retry strategy:

```ruby
# BAD: Passes entire object
class ProcessOrderJob < ApplicationJob
  def perform(order)
    # order is a serialized/deserialized AR object — stale data
    order.line_items.each do |item|
      item.product.decrement!(:stock, item.quantity)
    end
    OrderMailer.confirmation(order).deliver_now
    WarehouseApi.notify(order)
    Analytics.track("order_created", order.attributes)
    order.update!(processed: true)
  end
end
```

```ruby
# BAD: God job that does everything
class NightlyProcessingJob < ApplicationJob
  def perform
    # Recalculate all totals
    Order.find_each { |o| o.recalculate! }
    # Send reminder emails
    User.inactive.each { |u| ReminderMailer.nudge(u).deliver_now }
    # Clean up old records
    Order.where("created_at < ?", 1.year.ago).destroy_all
    # Generate reports
    ReportGenerator.monthly.generate!
    # Sync to external system
    ExternalSync.full_sync!
  end
end
```

## Why This Is Bad

- **Serialized objects are stale.** The order's data at enqueue time may differ from the database when the job runs (seconds, minutes, or hours later). The price could change, the status could update, line items could be modified.
- **No idempotency.** If `ProcessOrderJob` runs twice, stock is decremented twice, two confirmation emails are sent, and the warehouse is notified twice. Retries after a crash corrupt data.
- **God jobs can't be retried partially.** If `NightlyProcessingJob` fails during report generation, retrying it re-runs total recalculation, re-sends reminder emails, and re-deletes old records — all of which already completed.
- **No error isolation.** One failure in the god job kills the entire run. A network error in `ExternalSync.full_sync!` means reports don't generate and reminders don't send.
- **No queue differentiation.** Everything runs in the default queue. A burst of slow external API calls blocks email delivery.
- **`deliver_now` in a job.** Mailer delivery should use `deliver_now` inside a job (it's already async). But if the job itself fails and retries, the email sends again — unless you add an idempotency check.

## When To Apply

Move work to a background job when ANY of these are true:

- **External API calls** — HTTP requests to payment providers, notification services, webhooks. These are slow, unreliable, and shouldn't block a web response.
- **Email delivery** — Always `deliver_later`, never `deliver_now` in a controller. Let the job handle retries.
- **Data processing** — Recalculations, imports, exports, reports. These can take seconds or minutes and shouldn't tie up a web worker.
- **User-facing response doesn't need the result.** If the user doesn't need to see the outcome immediately (like "your report is being generated"), do it in a background job.

## When NOT To Apply

- **Don't background everything.** A 50ms database write that the user needs to see the result of (creating a comment, updating a profile) should happen synchronously in the request. Adding a job adds latency (Redis round trip + queue wait) for no benefit.
- **Don't use jobs for request-response patterns.** If the user is waiting for a result (like a refactored code response), use streaming — not "enqueue a job and poll for completion."
- **Don't create jobs for operations that must be transactional with the web request.** If creating an order and deducting credits must succeed or fail together, do both in the request within a transaction.

## Edge Cases

**Job needs to run after a transaction commits:**
Use `after_commit` or `ActiveRecord::Base.after_transaction` to ensure the record is visible to the job:

```ruby
# In a service object
def call
  ActiveRecord::Base.transaction do
    order = Order.create!(params)
    # Job runs AFTER the transaction commits
    order.run_callbacks(:commit) { OrderConfirmationJob.perform_later(order.id) }
  end
end

# Or in the model
after_commit :send_confirmation, on: :create

def send_confirmation
  OrderConfirmationJob.perform_later(id)
end
```

**Unique jobs (prevent duplicates):**
Use `sidekiq-unique-jobs` or check within the job:

```ruby
class IndexCodebaseJob < ApplicationJob
  def perform(project_id)
    project = Project.find(project_id)
    return if project.indexing?  # Already running

    project.update!(indexing: true)
    # ... do work ...
    project.update!(indexing: false)
  end
end
```

**Long-running jobs:**
Break into smaller jobs that each process a chunk:

```ruby
class BulkImportJob < ApplicationJob
  def perform(file_path, offset: 0, batch_size: 1000)
    rows = CSV.read(file_path)[offset, batch_size]
    return if rows.blank?

    rows.each { |row| import_row(row) }

    # Enqueue next batch
    BulkImportJob.perform_later(file_path, offset: offset + batch_size, batch_size: batch_size)
  end
end
```

**Testing jobs:**
Test the job logic directly with `perform_now`. Test the enqueuing separately.

```ruby
it "sends confirmation" do
  order = create(:order)
  expect { OrderConfirmationJob.perform_now(order.id) }
    .to change { ActionMailer::Base.deliveries.count }.by(1)
end

it "enqueues on order creation" do
  expect { create(:order) }
    .to have_enqueued_job(OrderConfirmationJob)
end
```
