# Gem: Devise

## What It Is

Devise is the standard Rails authentication gem. It handles registration, login, logout, password reset, email confirmation, account locking, and session management. It's built on Warden (Rack middleware) and provides generators, routes, views, and controllers out of the box.

## Setup Done Right

```ruby
# Gemfile
gem 'devise'

# After bundle install
rails generate devise:install
rails generate devise User
rails db:migrate

# config/initializers/devise.rb — the settings that matter
Devise.setup do |config|
  config.mailer_sender = 'noreply@rubyn.ai'

  # IMPORTANT: Set these in production
  config.pepper = ENV.fetch('DEVISE_PEPPER')           # Extra layer on bcrypt
  config.secret_key = ENV.fetch('DEVISE_SECRET_KEY')   # For token generation

  # Password requirements
  config.password_length = 8..128
  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/         # Simpler, less false rejections

  # Lockable — lock after failed attempts
  config.lock_strategy = :failed_attempts
  config.unlock_strategy = :both                        # Email + time
  config.maximum_attempts = 5
  config.unlock_in = 1.hour

  # Confirmable — if you use it
  config.confirm_within = 3.days
  config.reconfirmable = true

  # Rememberable
  config.remember_for = 2.weeks
  config.extend_remember_period = true                  # Resets timer on each visit

  # Timeoutable — session timeout
  config.timeout_in = 30.minutes
end
```

## Gotcha #1: Strong Parameters

Devise uses its own parameter sanitizer, NOT standard Rails strong params. If you add fields to the User model (like `name`), they'll be silently dropped unless you configure the sanitizer.

```ruby
# WRONG: This does nothing for Devise actions
class UsersController < ApplicationController
  def user_params
    params.require(:user).permit(:email, :password, :name)
  end
end

# RIGHT: Configure in ApplicationController
class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    # sign_up: registration#create
    devise_parameter_sanitizer.permit(:sign_up, keys: [:name, :company_name])

    # account_update: registration#update
    devise_parameter_sanitizer.permit(:account_update, keys: [:name, :avatar])

    # sign_in: session#create (rarely needed)
    devise_parameter_sanitizer.permit(:sign_in, keys: [:otp_attempt])
  end
end
```

**The trap:** You add a `name` field to the registration form, it submits correctly, but the name is never saved. No error, no warning — Devise silently drops unpermitted params. Check the server logs for "Unpermitted parameter: :name".

## Gotcha #2: Customizing Controllers

When you override a Devise controller, you MUST tell the router to use your controller, AND you must call `super` or replicate Devise's internal flow correctly.

```ruby
# Generate custom controllers
rails generate devise:controllers users -c=registrations sessions

# config/routes.rb — MUST point to your controllers
devise_for :users, controllers: {
  registrations: 'users/registrations',
  sessions: 'users/sessions'
}

# app/controllers/users/registrations_controller.rb
class Users::RegistrationsController < Devise::RegistrationsController
  # CORRECT: Call super and add your logic around it
  def create
    super do |user|
      # This block runs after the user is built but before redirect
      if user.persisted?
        Projects::CreateDefaultService.call(user)
        WelcomeMailer.welcome(user).deliver_later
      end
    end
  end

  # WRONG: Completely reimplementing create without understanding Devise's flow
  # def create
  #   @user = User.new(user_params)
  #   if @user.save
  #     redirect_to root_path
  #     # Missing: sign_in, flash, respond_with, location, etc.
  #   end
  # end

  protected

  # Where to redirect after signup
  def after_sign_up_path_for(resource)
    dashboard_path
  end

  # Where to redirect after update
  def after_update_path_for(resource)
    edit_user_registration_path
  end
end
```

**The trap:** You override `create` without calling `super`. Sign-up "works" but: the user isn't signed in, the flash message is missing, the Warden session isn't set correctly, `current_user` returns nil on the next page, and Turbo/Hotwire breaks because Devise's `respond_with` isn't called.

## Gotcha #3: `current_user` Is Nil in Unexpected Places

`current_user` relies on Warden middleware. It's not available in models, service objects, mailers, or background jobs.

```ruby
# WRONG: current_user in a model
class Order < ApplicationRecord
  before_create :set_creator
  def set_creator
    self.created_by = current_user  # NoMethodError — models don't have current_user
  end
end

# RIGHT: Use Current attributes or pass the user explicitly
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end

# Set in ApplicationController
class ApplicationController < ActionController::Base
  before_action :set_current_user

  private

  def set_current_user
    Current.user = current_user
  end
end

# Now available everywhere in the request cycle (but NOT in background jobs)
class Order < ApplicationRecord
  before_create :set_creator
  def set_creator
    self.created_by = Current.user&.id
  end
end
```

**The trap:** `Current.user` is request-scoped. In Sidekiq jobs, it's nil. Always pass user_id explicitly to background jobs.

## Gotcha #4: Password Change Requires Current Password

By default, Devise requires `current_password` for any registration update. This catches people when building profile edit pages.

```ruby
# The form MUST include current_password for updates
<%= form_for(resource, as: resource_name, url: registration_path(resource_name), method: :put) do |f| %>
  <%= f.text_field :name %>
  <%= f.email_field :email %>

  <%# THIS IS REQUIRED or the update silently fails %>
  <%= f.password_field :current_password, autocomplete: "current-password" %>

  <%= f.submit "Update" %>
<% end %>
```

If you want to update profile fields WITHOUT requiring the password:

```ruby
class Users::RegistrationsController < Devise::RegistrationsController
  protected

  # Allow update without password when not changing email/password
  def update_resource(resource, params)
    if params[:password].blank? && params[:password_confirmation].blank?
      params.delete(:password)
      params.delete(:password_confirmation)
      params.delete(:current_password)
      resource.update(params)
    else
      super
    end
  end
end
```

## Gotcha #5: Turbo/Hotwire Compatibility (Rails 7+)

Devise was built before Turbo. Without configuration, failed login/signup forms break because Devise returns HTTP 200 (which Turbo interprets as success) instead of 422.

```ruby
# config/initializers/devise.rb
Devise.setup do |config|
  # Rails 7+ with Turbo: Devise must return proper error status codes
  config.responder.error_status = :unprocessable_entity       # 422 for validation failures
  config.responder.redirect_status = :see_other               # 303 for redirects
end

# If you're on Devise < 4.9, you need this in ApplicationController:
class ApplicationController < ActionController::Base
  class Responder < ActionController::Responder
    def to_turbo_stream
      controller.render(options.merge(formats: :html))
    rescue ActionView::MissingTemplate => e
      if get?
        raise e
      elsif has_errors? && default_action
        render rendering_options.merge(formats: :html, status: :unprocessable_entity)
      else
        redirect_to navigation_location
      end
    end
  end

  self.responder = Responder
  respond_to :html, :turbo_stream
end
```

**The trap:** You submit a login form with wrong credentials. The page appears to do nothing — no error messages, no redirect. The form just sits there. The response was actually a 200 with error HTML, but Turbo expected 422 to know it should replace the form.

## Gotcha #6: Token Authentication for APIs

Devise doesn't ship with token auth. Don't try to hack `authenticate_with_http_token` onto Devise — use a separate strategy.

```ruby
# WRONG: Trying to use Devise for API auth
class Api::BaseController < ActionController::API
  before_action :authenticate_user!  # This uses session/cookie — doesn't work for APIs
end

# RIGHT: Separate API authentication
class Api::BaseController < ActionController::API
  before_action :authenticate_api_key!

  private

  def authenticate_api_key!
    token = request.headers["Authorization"]&.remove("Bearer ")
    @current_user = ApiKey.find_by(key_digest: Digest::SHA256.hexdigest(token.to_s))&.user
    head :unauthorized unless @current_user
  end

  def current_user
    @current_user
  end
end
```

For JWT-based API auth, use `devise-jwt` or `doorkeeper`. Don't roll your own JWT implementation.

## Gotcha #7: Testing with Devise

```ruby
# spec/support/devise.rb
RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
end

# In request specs — use sign_in helper
RSpec.describe "Orders", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it "lists orders" do
    get orders_path
    expect(response).to have_http_status(:ok)
  end
end

# WRONG: Trying to use sign_in in a model or service spec
# sign_in is a request/controller helper — it sets the Warden session
# In service specs, just pass the user directly

# For API specs with token auth — don't use sign_in
RSpec.describe "API Orders", type: :request do
  let(:user) { create(:user) }
  let(:api_key) { create(:api_key, user: user) }

  it "requires auth" do
    get "/api/v1/orders"
    expect(response).to have_http_status(:unauthorized)
  end

  it "works with valid key" do
    get "/api/v1/orders", headers: { "Authorization" => "Bearer #{api_key.raw_key}" }
    expect(response).to have_http_status(:ok)
  end
end
```

## Gotcha #8: Custom Mailer

Devise's default mailer sends plain text from `devise/mailer/`. To customize:

```ruby
# Generate views first
rails generate devise:views

# For a fully custom mailer:
# config/initializers/devise.rb
config.mailer = 'CustomDeviseMailer'

# app/mailers/custom_devise_mailer.rb
class CustomDeviseMailer < Devise::Mailer
  helper :application
  include Devise::Controllers::UrlHelpers
  layout 'mailer'

  def reset_password_instructions(record, token, opts = {})
    opts[:subject] = "Reset your Rubyn password"
    super
  end

  def confirmation_instructions(record, token, opts = {})
    opts[:subject] = "Confirm your Rubyn account"
    super
  end
end
```

**The trap:** You create `app/views/devise/mailer/reset_password_instructions.html.erb` but emails still use the old template. Devise caches views — restart the server. If using a custom mailer class, the views should be at `app/views/custom_devise_mailer/`.

## Do's and Don'ts Summary

**DO:**
- Set `pepper` and `secret_key` from ENV in production
- Configure parameter sanitizer for any custom fields
- Use `after_sign_up_path_for` and `after_sign_in_path_for` for redirects
- Set Turbo-compatible error/redirect status codes
- Use `sign_in` helper in request specs
- Use `Current.user` instead of threading `current_user` through every method call

**DON'T:**
- Don't override Devise controllers without calling `super` or fully understanding the flow
- Don't use Devise session auth for APIs — use token/JWT auth separately
- Don't put `current_user` in models, mailers, or jobs — it doesn't exist there
- Don't forget `current_password` in the update form
- Don't use `devise :token_authenticatable` — it was removed for security reasons
- Don't store passwords in ENV or logs — Devise handles hashing, but make sure `filter_parameters` includes `:password`
