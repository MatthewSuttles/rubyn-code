# SOLID: Liskov Substitution Principle (LSP)

## Pattern

If code works with a parent type, it must also work with any subtype without knowing the difference. Subtypes must honor the parent's contract — same method signatures, compatible return types, no strengthened preconditions, no weakened postconditions.

In Ruby, LSP applies to duck typing: any object that claims to implement an interface must behave consistently with other objects that implement that interface.

```ruby
# GOOD: Both notifiers honor the same contract
# Contract: #deliver(user, message) → sends a notification, returns a Result

class Notifications::EmailNotifier
  def deliver(user, message)
    NotificationMailer.notify(user.email, message).deliver_later
    Result.new(success: true, channel: :email)
  rescue Net::SMTPError => e
    Result.new(success: false, channel: :email, error: e.message)
  end
end

class Notifications::SmsNotifier
  def deliver(user, message)
    truncated = message.truncate(160)
    SmsClient.send(user.phone, truncated)
    Result.new(success: true, channel: :sms)
  rescue SmsClient::DeliveryError => e
    Result.new(success: false, channel: :sms, error: e.message)
  end
end

class Notifications::SlackNotifier
  def deliver(user, message)
    SlackClient.post(channel: user.slack_channel, text: message)
    Result.new(success: true, channel: :slack)
  rescue Slack::Web::Api::Errors::ChannelNotFound => e
    Result.new(success: false, channel: :slack, error: e.message)
  end
end

# The dispatcher doesn't know or care which notifier it's using
# Any notifier is substitutable for any other — LSP satisfied
class Notifications::Dispatcher
  def initialize(notifiers:)
    @notifiers = notifiers
  end

  def broadcast(user, message)
    @notifiers.map { |notifier| notifier.deliver(user, message) }
  end
end

# All substitutable
dispatcher = Notifications::Dispatcher.new(notifiers: [
  Notifications::EmailNotifier.new,
  Notifications::SmsNotifier.new,
  Notifications::SlackNotifier.new
])
results = dispatcher.broadcast(user, "Your order shipped!")
```

LSP with inheritance:

```ruby
# GOOD: Subclasses extend, they don't contradict
class Report
  def generate(start_date, end_date)
    data = fetch_data(start_date, end_date)
    format(data)
  end

  private

  def fetch_data(start_date, end_date)
    raise NotImplementedError
  end

  def format(data)
    raise NotImplementedError
  end
end

class RevenueReport < Report
  private

  def fetch_data(start_date, end_date)
    Order.where(created_at: start_date..end_date).group(:status).sum(:total)
  end

  def format(data)
    data.map { |status, total| "#{status}: $#{total}" }.join("\n")
  end
end

class UserActivityReport < Report
  private

  def fetch_data(start_date, end_date)
    User.where(last_active_at: start_date..end_date).group_by_day(:last_active_at).count
  end

  def format(data)
    data.map { |date, count| "#{date}: #{count} active users" }.join("\n")
  end
end

# Any Report subclass can be used anywhere a Report is expected
def email_report(report, recipient, start_date, end_date)
  content = report.generate(start_date, end_date)  # Works for any subclass
  ReportMailer.send(recipient, content).deliver_later
end

email_report(RevenueReport.new, "cfo@company.com", 30.days.ago, Date.today)
email_report(UserActivityReport.new, "pm@company.com", 7.days.ago, Date.today)
```

## Why This Is Good

- **Substitutable objects enable polymorphism.** The `Dispatcher` works with any notifier. `email_report` works with any report. Code that depends on the interface is decoupled from specific implementations.
- **Consistent contracts prevent surprises.** Every notifier returns a `Result` with `success?`, `channel`, and `error`. Code that processes results doesn't need special handling for each notifier type.
- **Error handling is uniform.** Each notifier catches its own exceptions and returns a `Result`. The dispatcher never sees a raw `Net::SMTPError` or `Slack::Web::Api::Errors::ChannelNotFound` — the notifiers normalize errors into the shared contract.
- **New types are safe.** Adding a `PushNotifier` is safe as long as it returns a `Result` from `deliver`. No existing code needs to know about push notifications.

## Anti-Pattern

A subtype that violates the parent's contract:

```ruby
class FileStorage
  def save(key, content)
    File.write(storage_path(key), content)
    true
  end

  def read(key)
    File.read(storage_path(key))
  end

  def delete(key)
    File.delete(storage_path(key))
    true
  end
end

class ReadOnlyStorage < FileStorage
  def save(key, content)
    raise NotImplementedError, "ReadOnlyStorage cannot save"
  end

  def delete(key)
    raise NotImplementedError, "ReadOnlyStorage cannot delete"
  end
end

# This breaks LSP:
def backup(storage, data)
  storage.save("backup-#{Date.today}", data)  # BOOM for ReadOnlyStorage
end

backup(FileStorage.new, data)       # Works
backup(ReadOnlyStorage.new, data)   # Raises NotImplementedError
```

```ruby
# Another violation: changing return types
class UserFinder
  def find(id)
    User.find(id)  # Returns a User or raises RecordNotFound
  end
end

class CachedUserFinder < UserFinder
  def find(id)
    Rails.cache.fetch("user:#{id}") do
      User.find_by(id: id)  # Returns nil instead of raising! Contract broken.
    end
  end
end
```

## Why This Is Bad

- **`ReadOnlyStorage` can't substitute for `FileStorage`.** Any code expecting a `FileStorage` that calls `save` will crash. The subclass has *strengthened the precondition* (you can't call save) — a direct LSP violation.
- **`CachedUserFinder` changes the contract.** `UserFinder#find` raises on missing records. `CachedUserFinder#find` returns `nil`. Code that relies on the exception for flow control will silently get `nil` and crash later with a `NoMethodError` on `nil`.
- **Type checks appear.** When subtypes are unreliable, callers start adding `is_a?` checks: `if storage.is_a?(ReadOnlyStorage)`. This defeats the purpose of polymorphism and creates brittle, coupled code.

## When To Apply

- **Whenever you use duck typing.** If two objects respond to the same method, they must behave the same way — same parameters accepted, same return type, same error behavior.
- **Whenever you inherit.** Subclasses must not remove capabilities, change return types, or raise unexpected exceptions. If a subclass needs to behave differently, it probably shouldn't be a subclass.
- **When designing interfaces for plugins or strategies.** Document the contract: what methods, what parameters, what return types, what errors. Every implementation must honor the contract.

## When NOT To Apply

- **Template Method pattern legitimately varies behavior.** `Report#fetch_data` raises `NotImplementedError` in the base class — subclasses are *expected* to override it. This isn't an LSP violation because the base class is abstract; no code calls `Report.new.generate` directly.
- **Ruby doesn't have formal interfaces.** LSP in Ruby is about behavioral contracts, not type signatures. Two objects can have different class hierarchies and still be LSP-compliant if they honor the same duck-type contract.

## Edge Cases

**How to fix the ReadOnlyStorage problem:**
Don't inherit. Use separate interfaces:

```ruby
module Readable
  def read(key)
    raise NotImplementedError
  end
end

module Writable
  def save(key, content)
    raise NotImplementedError
  end

  def delete(key)
    raise NotImplementedError
  end
end

class FileStorage
  include Readable
  include Writable
  # ... implements all methods
end

class ReadOnlyStorage
  include Readable
  # Only read, never promises write
end

# Code that needs to write asks for Writable:
def backup(storage, data)
  # storage must include Writable — ReadOnlyStorage won't be passed here
  storage.save("backup", data)
end
```

**Testing LSP compliance:**
Shared examples enforce the contract across all implementations:

```ruby
RSpec.shared_examples "a notifier" do
  it "returns a Result from deliver" do
    result = subject.deliver(user, "test message")
    expect(result).to respond_to(:success?, :channel, :error)
  end

  it "returns success: true or false, never nil" do
    result = subject.deliver(user, "test")
    expect(result.success?).to be(true).or be(false)
  end
end

RSpec.describe Notifications::EmailNotifier do
  subject { described_class.new }
  it_behaves_like "a notifier"
end

RSpec.describe Notifications::SmsNotifier do
  subject { described_class.new }
  it_behaves_like "a notifier"
end
```
