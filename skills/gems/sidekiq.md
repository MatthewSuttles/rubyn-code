# Gem: Sidekiq

## What It Is

Sidekiq processes background jobs using Redis-backed queues. It's the standard for async work in Rails — sending emails, processing uploads, calling external APIs, and running scheduled tasks. It uses threads (not processes) for concurrency, so it's memory efficient but requires thread-safe code.

## Setup Done Right

```ruby
# Gemfile
gem 'sidekiq'

# config/application.rb
config.active_job.queue_adapter = :sidekiq

# config/initializers/sidekiq.rb
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end

# config/sidekiq.yml
:concurrency: 10
:queues:
  - [critical, 3]
  - [default, 2]
  - [low, 1]
```

## Gotcha #1: Jobs Must Be Idempotent

Sidekiq guarantees "at least once" delivery. Jobs can run multiple times due to network issues, process crashes, or manual retries. If your job isn't idempotent, duplicate execution causes real damage.

```ruby
# WRONG: Non-idempotent — double execution sends two emails
class OrderConfirmationJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find(order_id)
    OrderMailer.confirmation(order).deliver_now
  end
end

# RIGHT: Idempotent — second execution is a no-op
class OrderConfirmationJob < ApplicationJob
  queue_as :default

  def perform(order_id)
    order = Order.find(order_id)
    return if order.confirmation_sent_at.present?  # Already sent

    OrderMailer.confirmation(order).deliver_now
    order.update!(confirmation_sent_at: Time.current)
  end
end
```

```ruby
# WRONG: Non-idempotent — double execution double-charges
class ChargeJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    Stripe::Charge.create(amount: order.total_cents, source: order.payment_token)
    order.update!(paid: true)
  end
end

# RIGHT: Check before charging, use idempotency keys
class ChargeJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    return if order.paid?  # Already charged

    Stripe::Charge.create(
      amount: order.total_cents,
      source: order.payment_token,
      idempotency_key: "order-#{order.id}"  # Stripe deduplicates
    )
    order.update!(paid: true, paid_at: Time.current)
  end
end
```

**The trap:** The job runs, charges the card, then crashes before `update!(paid: true)`. Sidekiq retries. The card is charged again. Always check state before performing side effects, and use provider-level idempotency keys where available.

## Gotcha #2: Pass IDs, Not Objects

Sidekiq serializes arguments to JSON and stores them in Redis. ActiveRecord objects can't be serialized, and even if they could, they'd be stale by the time the job runs.

```ruby
# WRONG: Passing an ActiveRecord object
OrderConfirmationJob.perform_later(order)
# ArgumentError: ActiveRecord objects can't be serialized to JSON

# WRONG: Passing a hash of attributes
OrderConfirmationJob.perform_later(order.attributes)
# Works but: 30 fields serialized, most unused. Stale data if order changes before job runs.

# RIGHT: Pass the ID, load fresh data in the job
OrderConfirmationJob.perform_later(order.id)

# RIGHT: For multiple simple values, pass them directly
CreditDeductionJob.perform_later(user.id, 5, "AI interaction")
```

**The trap with ActiveJob:** ActiveJob has GlobalID which CAN serialize AR objects via `perform_later(order)`. But the object is loaded from the database when the job runs. If the record is deleted between enqueue and execution, you get `ActiveJob::DeserializationError`. Passing IDs and using `find_by` with nil handling is more robust.

```ruby
# SAFER: Handle missing records
class OrderConfirmationJob < ApplicationJob
  discard_on ActiveRecord::RecordNotFound

  def perform(order_id)
    order = Order.find(order_id)  # Raises if deleted — discard_on handles it
    # ...
  end
end
```

## Gotcha #3: Thread Safety

Sidekiq uses threads. Shared mutable state across threads causes race conditions.

```ruby
# WRONG: Class-level mutable state
class ImportJob < ApplicationJob
  @@processed_count = 0  # Shared across all threads!

  def perform(file_path)
    CSV.foreach(file_path) do |row|
      import_row(row)
      @@processed_count += 1  # Race condition: two threads increment simultaneously
    end
  end
end

# WRONG: Mutable instance variables that persist between jobs
class ApiClient
  def initialize
    @last_response = nil  # Sidekiq reuses the instance across jobs
  end
end

# RIGHT: Use local variables or thread-safe structures
class ImportJob < ApplicationJob
  def perform(file_path)
    count = 0  # Local to this execution
    CSV.foreach(file_path) do |row|
      import_row(row)
      count += 1
    end
    Rails.logger.info("Imported #{count} rows")
  end
end

# RIGHT: Use thread-safe operations for shared counters
class ImportJob < ApplicationJob
  def perform(file_path)
    # Redis is thread-safe — use it for shared state
    Redis.current.set("import:#{file_path}:status", "processing")
    # ...
    Redis.current.set("import:#{file_path}:status", "complete")
  end
end
```

**The trap:** Your job works perfectly in development (single thread). In production with `concurrency: 10`, two threads modify the same data and you get corrupted records, duplicate inserts, or wrong counts.

## Gotcha #4: Transaction + Job Enqueue Timing

If you enqueue a job inside a transaction that hasn't committed yet, the job might run before the transaction commits — and the record won't exist yet.

```ruby
# WRONG: Job fires before transaction commits
ActiveRecord::Base.transaction do
  order = Order.create!(params)
  OrderConfirmationJob.perform_later(order.id)  # Job starts immediately
  # Transaction hasn't committed yet — job might run and Order.find raises!
  update_inventory(order)
end

# RIGHT: Enqueue after the transaction commits
ActiveRecord::Base.transaction do
  order = Order.create!(params)
  update_inventory(order)
end
# Transaction committed — record exists in DB
OrderConfirmationJob.perform_later(order.id)

# RIGHT: Use after_commit callback
class Order < ApplicationRecord
  after_commit :send_confirmation, on: :create

  private

  def send_confirmation
    OrderConfirmationJob.perform_later(id)
  end
end
```

## Gotcha #5: Retry Strategy

Sidekiq retries failed jobs with exponential backoff by default (25 retries over ~21 days). This is usually too aggressive.

```ruby
# Configure retries per job
class WebhookDeliveryJob < ApplicationJob
  queue_as :webhooks

  # ActiveJob retry configuration
  retry_on Faraday::TimeoutError, wait: :polynomially_longer, attempts: 5
  retry_on Faraday::ServerError, wait: 30.seconds, attempts: 3
  discard_on Faraday::ClientError  # 4xx errors won't succeed on retry

  # OR: Sidekiq-native retry configuration (use one or the other, not both)
  sidekiq_options retry: 5

  def perform(webhook_id)
    webhook = Webhook.find(webhook_id)
    response = Faraday.post(webhook.url, webhook.payload.to_json)
    raise Faraday::ServerError, "HTTP #{response.status}" unless response.success?
  end
end

# Jobs that should NEVER retry
class OneTimeImportJob < ApplicationJob
  sidekiq_options retry: 0  # or: discard_on StandardError

  def perform(file_path)
    # ...
  end
end
```

**The trap:** A job that calls an external API fails. Sidekiq retries 25 times over 21 days. The external API was down for 5 minutes. After it recovers, your job retries with stale data from 3 weeks ago. Set appropriate retry limits and consider discarding jobs that are too old.

## Gotcha #6: Queue Priority Starvation

Sidekiq processes queues in the order listed. Without weights, a flood of low-priority jobs can starve critical ones.

```yaml
# WRONG: No weights — Sidekiq processes strictly in order
:queues:
  - critical
  - default
  - low
# If 1000 critical jobs are queued, default and low NEVER run until critical is empty

# RIGHT: Weighted queues
:queues:
  - [critical, 3]   # 3x more likely to be picked than low
  - [default, 2]    # 2x more likely than low
  - [low, 1]        # Baseline priority
```

```ruby
# Assign queues by job type
class PaymentJob < ApplicationJob
  queue_as :critical
end

class EmailJob < ApplicationJob
  queue_as :default
end

class ReportJob < ApplicationJob
  queue_as :low
end
```

## Gotcha #7: Memory and Large Arguments

Sidekiq stores job arguments in Redis. Large arguments consume Redis memory and slow down serialization.

```ruby
# WRONG: Passing large data through Redis
class ProcessDataJob < ApplicationJob
  def perform(csv_data)  # csv_data could be 50MB
    # This serializes 50MB to JSON, stores in Redis, deserializes in the worker
  end
end

# RIGHT: Pass a reference, load data in the job
class ProcessDataJob < ApplicationJob
  def perform(file_path)
    data = File.read(file_path)  # OR: ActiveStorage download
    process(data)
  end
end

# RIGHT: For S3/ActiveStorage files
class ProcessUploadJob < ApplicationJob
  def perform(blob_id)
    blob = ActiveStorage::Blob.find(blob_id)
    blob.open do |file|
      process(file)
    end
  end
end
```

## Gotcha #8: Testing Sidekiq Jobs

```ruby
# spec/jobs/order_confirmation_job_spec.rb
RSpec.describe OrderConfirmationJob, type: :job do
  let(:order) { create(:order) }

  # Test the job logic directly
  it "sends a confirmation email" do
    expect {
      described_class.perform_now(order.id)
    }.to change { ActionMailer::Base.deliveries.count }.by(1)
  end

  it "is idempotent" do
    described_class.perform_now(order.id)
    described_class.perform_now(order.id)
    expect(ActionMailer::Base.deliveries.count).to eq(1)  # Sent once, not twice
  end

  it "handles missing records" do
    expect { described_class.perform_now(999_999) }
      .not_to raise_error  # discard_on handles it
  end

  # Test that the job is enqueued
  it "is enqueued after order creation" do
    expect { create(:order) }
      .to have_enqueued_job(described_class)
      .with(kind_of(Integer))
      .on_queue("default")
  end
end
```

## Do's and Don'ts Summary

**DO:**
- Make every job idempotent — check state before acting
- Pass IDs, not objects or large data
- Use `discard_on` for errors that won't succeed on retry
- Set explicit retry counts per job type
- Use weighted queues to prevent starvation
- Enqueue jobs after transaction commit
- Test idempotency explicitly

**DON'T:**
- Don't use class variables or global mutable state in jobs
- Don't pass large payloads (>100KB) as job arguments
- Don't enqueue inside transactions without `after_commit`
- Don't assume jobs run exactly once — they run at least once
- Don't use the default 25 retries for everything
- Don't use `perform_now` in production code (defeats the purpose of async)
- Don't forget to start the Sidekiq process separately (`bundle exec sidekiq`)
