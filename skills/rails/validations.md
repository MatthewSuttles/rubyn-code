# Rails: Validations

## Pattern

Keep validations on the model for data integrity rules that must always be enforced. Use custom validators for complex or reusable validation logic. Use form objects for context-specific validations that only apply in certain flows.

```ruby
class User < ApplicationRecord
  # Simple, always-enforced validations
  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :name, presence: true, length: { maximum: 100 }
  validates :role, inclusion: { in: %w[user admin] }

  # Normalize before validating
  before_validation :normalize_email

  private

  def normalize_email
    self.email = email&.downcase&.strip
  end
end
```

```ruby
class Order < ApplicationRecord
  validates :shipping_address, presence: true
  validates :total, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: %w[pending confirmed shipped delivered cancelled] }

  # Custom validation method for complex business rules
  validate :line_items_must_be_present, on: :create
  validate :total_matches_line_items, on: :create

  private

  def line_items_must_be_present
    errors.add(:base, "Order must have at least one item") if line_items.empty?
  end

  def total_matches_line_items
    expected = line_items.sum { |li| li.quantity * li.unit_price }
    errors.add(:total, "doesn't match line items") unless total == expected
  end
end
```

Custom validator class for reusable validations:

```ruby
# app/validators/url_validator.rb
class UrlValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    uri = URI.parse(value)
    unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      record.errors.add(attribute, options[:message] || "must be a valid URL")
    end
  rescue URI::InvalidURIError
    record.errors.add(attribute, options[:message] || "must be a valid URL")
  end
end

# Usage in any model
class Company < ApplicationRecord
  validates :website, url: true
  validates :blog_url, url: { message: "must be a valid blog URL" }, allow_blank: true
end
```

## Why This Is Good

- **Data integrity at the model level.** No matter how a User is created (form, API, console, seed, test), the email will be present, unique, and formatted correctly. This is the last line of defense before the database.
- **Normalized before validation.** Downcasing the email before validating uniqueness prevents "Alice@Example.com" and "alice@example.com" from being treated as different emails.
- **Custom validator classes are reusable.** `UrlValidator` works on any model, any attribute. Write it once, use it everywhere with `validates :field, url: true`.
- **`on: :create` limits when validation runs.** Line items must be present when creating an order, but updating the shipping address later shouldn't fail because you didn't re-validate line items.
- **Errors are specific and attributable.** `errors.add(:total, "doesn't match")` ties the error to the field, enabling per-field error display in forms.

## Anti-Pattern

Scattering validations across callbacks, controllers, and duplicating database constraints:

```ruby
class User < ApplicationRecord
  validates :email, presence: true

  before_save :check_email_format
  after_validation :verify_email_dns
  before_create :ensure_unique_email

  private

  def check_email_format
    unless email =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
      errors.add(:email, "format is invalid")
      throw(:abort)
    end
  end

  def verify_email_dns
    # Slow DNS lookup on every validation
    domain = email.split("@").last
    unless Resolv::DNS.new.getresources(domain, Resolv::DNS::Resource::IN::MX).any?
      errors.add(:email, "domain doesn't accept email")
    end
  end

  def ensure_unique_email
    if User.exists?(email: email)
      errors.add(:email, "already taken")
      throw(:abort)
    end
  end
end
```

```ruby
# Also in the controller — duplicating model validation
class UsersController < ApplicationController
  def create
    if params[:user][:email].blank?
      flash[:error] = "Email is required"
      render :new and return
    end

    unless params[:user][:email] =~ /\A[\w+\-.]+@/
      flash[:error] = "Email format is invalid"
      render :new and return
    end

    @user = User.new(user_params)
    # ...
  end
end
```

## Why This Is Bad

- **Validation split across callbacks.** `before_save`, `after_validation`, and `before_create` all check the email. A developer reading the model has to trace through 3 callbacks to understand the full validation story. All of this belongs in `validates` declarations.
- **`throw(:abort)` in callbacks.** This halts the save silently. The caller gets `false` from `save` but the error might not be on the errors object if the throw happens in `before_save` after validation already passed.
- **DNS lookup on every validation.** Every `valid?` call triggers a network request. This slows tests, breaks offline development, and adds a failure mode to every form submission.
- **Race condition in `ensure_unique_email`.** Between the `exists?` check and the `save`, another request can create the same email. Use a `validates :email, uniqueness: true` plus a database unique index for real protection.
- **Duplicated validation in the controller.** The controller checks email presence and format, then the model checks again. When the rules change, you update one place and forget the other.

## When To Apply

- **Model validations for invariants.** Rules that must ALWAYS be true: email format, presence of required fields, numericality, inclusion in allowed values, uniqueness.
- **Custom validator classes for reusable rules.** URL format, phone number format, postal code format — anything used across multiple models.
- **`validate` methods for complex business rules** that involve relationships between attributes or associated records.
- **Always back uniqueness validations with a database unique index.** The validation provides a nice error message; the index prevents race conditions.

## When NOT To Apply

- **Don't validate in controllers.** The model is the single source of truth for data validity. Controllers check the result of `save`/`valid?` and respond accordingly.
- **Don't use `validates_associated` carelessly.** It validates every associated record on every save, which can cascade into slow, unexpected validation chains.
- **Don't put context-specific validations on the model.** If a field is required during registration but not during profile update, use a form object — not `validates :field, presence: true, on: :create`.
- **Don't validate external data in model validations.** DNS lookups, API calls, and other network requests don't belong in validations. They're slow, unreliable, and break tests.

## Edge Cases

**Conditional validations — `if:` and `unless:`:**
Use sparingly. A few conditional validations are fine. If the model has 5+ conditions, that's a sign you need form objects for different contexts.

```ruby
validates :shipping_address, presence: true, unless: :digital_product?
validates :download_url, presence: true, if: :digital_product?
```

**Validation contexts (`:on`):**
Built-in contexts are `:create` and `:update`. You can define custom contexts, but form objects are usually cleaner:

```ruby
# Model with custom context
validates :terms, acceptance: true, on: :registration

# Triggered explicitly
user.valid?(:registration)

# Better: use a form object instead
class RegistrationForm
  validates :terms, acceptance: true
end
```

**Database constraints as backup:**
Model validations provide user-friendly errors. Database constraints prevent data corruption. Use both:

```ruby
# Migration
add_index :users, :email, unique: true
change_column_null :users, :email, false

# Model
validates :email, presence: true, uniqueness: true
```

**`errors.add` to `:base` vs to an attribute:**
Add to `:base` when the error isn't attributable to a single field. Add to the attribute when it is.

```ruby
errors.add(:base, "Order total exceeds credit limit")  # Cross-field concern
errors.add(:email, "is already registered")              # Single field concern
```
