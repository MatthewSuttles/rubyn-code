# Refactoring: Extract Class

## Pattern

When a class has too many responsibilities — groups of data and methods that logically belong together — extract them into a new class. The original class delegates to the extracted class.

```ruby
# BEFORE: User model handles profile, settings, AND billing
class User < ApplicationRecord
  # Profile concern
  def full_name = "#{first_name} #{last_name}"
  def initials = "#{first_name[0]}#{last_name[0]}".upcase
  def display_name = nickname.presence || full_name
  def avatar_url = avatar.attached? ? avatar.url : gravatar_url
  def gravatar_url = "https://gravatar.com/avatar/#{Digest::MD5.hexdigest(email)}"

  # Billing concern
  def active_subscription = subscriptions.active.last
  def plan_name = active_subscription&.plan || "free"
  def credit_balance = credit_ledger_entries.sum(:amount)
  def can_afford?(credits) = credit_balance >= credits
  def deduct_credits!(amount)
    credit_ledger_entries.create!(amount: -amount, description: "Usage")
  end
  def billing_email = billing_email_override.presence || email
  def billing_address = addresses.find_by(type: "billing")

  # Settings concern
  def notification_preferences = settings.dig("notifications") || {}
  def email_notifications? = notification_preferences.fetch("email", true)
  def theme = settings.dig("appearance", "theme") || "system"
  def timezone = settings.dig("timezone") || "UTC"
  def locale = settings.dig("locale") || "en"
end
```

```ruby
# AFTER: Extracted into focused collaborators

class User < ApplicationRecord
  has_one :profile, dependent: :destroy
  has_one :billing_account, dependent: :destroy
  has_one :user_settings, dependent: :destroy

  delegate :full_name, :initials, :display_name, :avatar_url, to: :profile
  delegate :credit_balance, :can_afford?, :deduct_credits!, :plan_name, to: :billing_account
  delegate :email_notifications?, :theme, :timezone, :locale, to: :user_settings
end

class Profile < ApplicationRecord
  belongs_to :user

  def full_name = "#{user.first_name} #{user.last_name}"
  def initials = "#{user.first_name[0]}#{user.last_name[0]}".upcase
  def display_name = nickname.presence || full_name
  def avatar_url = avatar.attached? ? avatar.url : gravatar_url

  private

  def gravatar_url = "https://gravatar.com/avatar/#{Digest::MD5.hexdigest(user.email)}"
end

class BillingAccount < ApplicationRecord
  belongs_to :user
  has_many :credit_ledger_entries
  has_many :subscriptions

  def active_subscription = subscriptions.active.last
  def plan_name = active_subscription&.plan || "free"
  def credit_balance = credit_ledger_entries.sum(:amount)
  def can_afford?(credits) = credit_balance >= credits

  def deduct_credits!(amount)
    credit_ledger_entries.create!(amount: -amount, description: "Usage")
  end
end

class UserSettings < ApplicationRecord
  belongs_to :user

  def email_notifications? = preferences.dig("notifications", "email") != false
  def theme = preferences.dig("appearance", "theme") || "system"
  def timezone = preferences.dig("timezone") || "UTC"
  def locale = preferences.dig("locale") || "en"
end
```

## Why This Is Good

- **Each class has one reason to change.** Billing rule changes touch `BillingAccount`. Display changes touch `Profile`. Notification settings touch `UserSettings`. The `User` model stays stable.
- **Smaller classes are easier to understand.** `BillingAccount` has 5 methods about billing. Reading it, you grasp the entire billing interface in 30 seconds.
- **Better testing.** Test `BillingAccount#deduct_credits!` without loading profile logic, settings, or 20 other user methods.
- **`delegate` maintains the interface.** Callers still call `user.credit_balance`. The extraction is invisible to external code.

# Refactoring: Move Method

## Pattern

When a method uses more features of another class than the class it's defined on, move it to where the data lives.

```ruby
# BEFORE: Method on Order that mostly accesses User data
class Order < ApplicationRecord
  def customer_summary
    "#{user.name} (#{user.email}) — #{user.plan_name} plan, #{user.orders.count} orders, " \
      "member since #{user.created_at.year}"
  end
end

# AFTER: Method moved to User where the data lives
class User < ApplicationRecord
  def customer_summary
    "#{name} (#{email}) — #{plan_name} plan, #{orders.count} orders, member since #{created_at.year}"
  end
end

# Order delegates or the caller accesses directly
order.user.customer_summary
```

## When To Apply Extract Class

- **A class has 200+ lines.** Look for clusters of related methods to extract.
- **You can describe the class with "and."** "User handles authentication AND billing AND settings" → extract billing and settings.
- **Multiple developers frequently edit the same file.** Different teams own different responsibilities → different classes.
- **A group of methods share the same instance variables.** Methods that all use `@subscription` and `@credit_entries` are a billing class waiting to be extracted.

## When To Apply Move Method

- **Feature Envy.** A method references another object 3+ times and its own object 0-1 times.
- **After Extract Class.** Once you identify a cluster, move the methods to the new class.
- **When adding `delegate` chains.** If `User` delegates 5 methods to `BillingAccount` and then adds `billing_` prefix methods, maybe those callers should reference `BillingAccount` directly.

## When NOT To Apply

- **Don't extract prematurely.** A User model with 80 lines and 8 methods is fine. Extract when it grows past 150-200 lines or when the clusters become obvious.
- **Don't create single-method classes.** A `UserGreeter` with just `def greet` is over-extraction. The method can live on User.
- **Delegate is fine for 3-5 methods.** If User delegates 15 methods to a single collaborator, callers should reference the collaborator directly.
