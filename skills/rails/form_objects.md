# Rails: Form Objects

## Pattern

Use form objects when a form doesn't map cleanly to a single ActiveRecord model. Form objects encapsulate validation, data transformation, and multi-model persistence behind an ActiveModel-compliant interface that works with Rails form helpers.

```ruby
# app/forms/registration_form.rb
class RegistrationForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :email, :string
  attribute :password, :string
  attribute :password_confirmation, :string
  attribute :company_name, :string
  attribute :plan, :string, default: "free"
  attribute :terms_accepted, :boolean

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, presence: true, length: { minimum: 8 }
  validates :password_confirmation, presence: true
  validates :company_name, presence: true
  validates :terms_accepted, acceptance: true
  validate :passwords_match
  validate :email_not_taken

  def save
    return false unless valid?

    ActiveRecord::Base.transaction do
      company = Company.create!(name: company_name, plan: plan)
      user = company.users.create!(email: email, password: password, role: :admin)
      Onboarding::WelcomeService.call(user)
    end

    true
  rescue ActiveRecord::RecordInvalid => e
    errors.add(:base, e.message)
    false
  end

  private

  def passwords_match
    errors.add(:password_confirmation, "doesn't match") unless password == password_confirmation
  end

  def email_not_taken
    errors.add(:email, "is already registered") if User.exists?(email: email)
  end
end
```

The controller stays thin:

```ruby
# app/controllers/registrations_controller.rb
class RegistrationsController < ApplicationController
  def new
    @form = RegistrationForm.new
  end

  def create
    @form = RegistrationForm.new(registration_params)

    if @form.save
      redirect_to dashboard_path, notice: "Welcome!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:registration_form).permit(:email, :password, :password_confirmation, :company_name, :plan, :terms_accepted)
  end
end
```

The view works with standard form helpers:

```erb
<%= form_with model: @form, url: registrations_path do |f| %>
  <%= f.text_field :email %>
  <%= f.password_field :password %>
  <%= f.password_field :password_confirmation %>
  <%= f.text_field :company_name %>
  <%= f.check_box :terms_accepted %>
  <%= f.submit "Sign Up" %>
<% end %>
```

## Why This Is Good

- **Validates as a unit.** Cross-field validations (password confirmation, terms acceptance) and cross-model checks (email uniqueness) live together in one object rather than scattered across multiple models.
- **Works with Rails forms.** Including `ActiveModel::Model` gives you `form_with` compatibility, error messages, and all the form helpers for free.
- **Keeps models clean.** The User model doesn't need a `terms_accepted` virtual attribute or a `password_confirmation` validation that only applies during registration.
- **Testable.** Instantiate the form with params, call `.save`, assert results. No HTTP, no controllers, no views.
- **Transactional.** Multi-model persistence wraps in a transaction naturally within the `save` method.

## Anti-Pattern

Stuffing virtual attributes and context-specific validations into the model:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  attr_accessor :company_name, :plan, :terms_accepted, :registering

  validates :terms_accepted, acceptance: true, if: :registering
  validates :password_confirmation, presence: true, if: :registering
  validates :company_name, presence: true, if: :registering

  after_create :create_company_and_onboard, if: :registering

  private

  def create_company_and_onboard
    company = Company.create!(name: company_name, plan: plan)
    self.update!(company: company, role: :admin)
    Onboarding::WelcomeService.call(self)
  end
end
```

## Why This Is Bad

- **Conditional validations pollute the model.** Every `if: :registering` is a code smell. The model accumulates flags and conditionals for every context it's used in (registration, profile update, admin edit, API creation).
- **Virtual attributes bloat the model.** `company_name`, `plan`, `terms_accepted` have nothing to do with the User model — they're registration-specific concerns.
- **Callbacks hide side effects.** `after_create :create_company_and_onboard` runs silently whenever a user is created with the `registering` flag. Creating a user in the console, a seed file, or a test unexpectedly triggers company creation if someone accidentally sets the flag.
- **Hard to test.** Testing registration requires setting `user.registering = true` and knowing about the hidden callback chain. The test is coupled to implementation details.

## When To Apply

Use a form object when ANY of these are true:

- The form spans **multiple models** (registration creates a user AND a company)
- The form has **virtual attributes** that don't exist on any model (terms acceptance, password confirmation for non-Devise setups, promotional codes)
- **Validations are context-specific** — they apply during this form submission but not when the model is used elsewhere
- The form requires **data transformation** before persistence (parsing dates, splitting full name into first/last, geocoding an address)
- The form has **complex conditional logic** about which fields are required based on other field values

## When NOT To Apply

- The form maps **directly to one model** with no virtual attributes and no context-specific validations. Use the model directly — a form object adds a pointless layer.
- The form is **read-only** (search, filter). Use a simple parameter object or a query object instead.
- The **only difference** from the model is one extra validation. Add it to the model with a context (`validates :field, presence: true, on: :registration`) rather than creating an entire form object for one rule.

## Edge Cases

**The form needs to update existing records, not just create:**
Add a constructor that accepts an existing record and populates attributes from it. The `save` method checks for `persisted?` and calls `update!` instead of `create!`.

```ruby
def initialize(user: nil, **attributes)
  @user = user
  super(**attributes)
  self.email ||= @user&.email
end
```

**The form has nested attributes (like line items on an order):**
Form objects can include their own nested form objects or accept arrays. This is where form objects really shine over `accepts_nested_attributes_for`, which is brittle and hard to validate.

**The team uses the `reform` or `dry-validation` gem:**
Follow the team's existing pattern. If they use Reform, write a Reform form. Rubyn adapts to the project's conventions.
