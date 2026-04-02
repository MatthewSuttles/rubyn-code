# Rails: Security

## Pattern

Security is not a feature — it's a property of every feature. Rails provides strong defaults, but you must use them correctly. This document covers the critical security practices for every Rails application.

### Strong Parameters (Mass Assignment Protection)

```ruby
# GOOD: Explicitly permit only expected params
class OrdersController < ApplicationController
  private

  def order_params
    params.require(:order).permit(:shipping_address, :notes,
      line_items_attributes: [:product_id, :quantity])
  end
end

# BAD: Permitting everything
def order_params
  params.require(:order).permit!  # NEVER do this
end

# BAD: Permitting role or admin fields
def user_params
  params.require(:user).permit(:name, :email, :role, :admin)  # User can make themselves admin!
end

# GOOD: Separate param sets for different contexts
def user_params
  params.require(:user).permit(:name, :email)
end

def admin_user_params
  params.require(:user).permit(:name, :email, :role, :admin)  # Only in admin controllers
end
```

### SQL Injection Prevention

```ruby
# GOOD: Parameterized queries (Rails does this by default)
User.where(email: params[:email])
User.where("email = ?", params[:email])
User.where("email = :email", email: params[:email])
Order.where(status: params[:status], user_id: current_user.id)

# BAD: String interpolation in SQL
User.where("email = '#{params[:email]}'")         # SQL injection!
Order.where("status = #{params[:status]}")          # SQL injection!
User.order("#{params[:sort_column]} #{params[:sort_direction]}")  # SQL injection!

# GOOD: Safe column sorting
ALLOWED_SORT_COLUMNS = %w[created_at total status].freeze
ALLOWED_DIRECTIONS = %w[asc desc].freeze

def safe_order(scope)
  column = ALLOWED_SORT_COLUMNS.include?(params[:sort]) ? params[:sort] : "created_at"
  direction = ALLOWED_DIRECTIONS.include?(params[:dir]) ? params[:dir] : "desc"
  scope.order(column => direction)
end
```

### XSS (Cross-Site Scripting) Prevention

```ruby
# GOOD: Rails auto-escapes by default in ERB
<%= user.name %>  <%# Automatically escaped — safe %>

# BAD: raw/html_safe bypasses escaping
<%= raw user.bio %>          # If bio contains <script>, it executes!
<%= user.bio.html_safe %>    # Same vulnerability

# GOOD: When you need HTML, sanitize it
<%= sanitize user.bio, tags: %w[p br strong em a], attributes: %w[href] %>

# GOOD: JSON in script tags (Rails 7+)
<script>
  const data = <%= raw json_escape(data.to_json) %>;
</script>

# Or better — use data attributes
<div data-order="<%= order.to_json %>">
```

### CSRF Protection

```ruby
# Rails includes CSRF protection by default for HTML forms
class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
end

# API controllers skip CSRF (they use token auth instead)
class Api::BaseController < ActionController::API
  # No CSRF — API uses Bearer token authentication
end
```

### Authentication Security

```ruby
# GOOD: Secure API key storage — hash the key, store the hash
class ApiKey < ApplicationRecord
  before_create :generate_key_pair

  # Store only the hash — never the raw key
  def self.find_by_token(raw_token)
    hashed = Digest::SHA256.hexdigest(raw_token)
    find_by(key_hash: hashed, revoked_at: nil)
  end

  private

  def generate_key_pair
    raw_key = SecureRandom.urlsafe_base64(32)
    self.key_hash = Digest::SHA256.hexdigest(raw_key)
    self.key_prefix = raw_key[0..7]  # For identification in UI

    # Return the raw key ONCE — it's never stored
    @raw_key = raw_key
  end
end

# GOOD: Constant-time comparison to prevent timing attacks
def authenticate_token(provided_token)
  expected_hash = Digest::SHA256.hexdigest(provided_token)
  api_key = ApiKey.find_by(key_prefix: provided_token[0..7])
  return nil unless api_key

  # Constant-time comparison
  ActiveSupport::SecurityUtils.secure_compare(api_key.key_hash, expected_hash) ? api_key : nil
end

# GOOD: Password requirements with Devise
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :lockable, :trackable

  validates :password, length: { minimum: 8 }, if: :password_required?
end
```

### Authorization (Scoping Queries)

```ruby
# GOOD: Always scope queries to the current user
class OrdersController < ApplicationController
  def show
    @order = current_user.orders.find(params[:id])
    # If the order doesn't belong to current_user, raises RecordNotFound (404)
  end

  def index
    @orders = current_user.orders.recent
    # Never see other users' orders
  end
end

# BAD: Global lookup — any user can access any order
class OrdersController < ApplicationController
  def show
    @order = Order.find(params[:id])  # IDOR vulnerability!
  end
end
```

### Secrets Management

```ruby
# GOOD: Use Rails credentials
# Edit: rails credentials:edit
# Access:
Rails.application.credentials.anthropic_api_key
Rails.application.credentials.dig(:database, :password)

# GOOD: Environment variables for deployment
ENV.fetch("ANTHROPIC_API_KEY")  # Fails loudly if missing
ENV["OPTIONAL_KEY"]             # Returns nil if missing

# BAD: Secrets in code
ANTHROPIC_API_KEY = "sk-ant-abc123..."  # NEVER commit secrets

# BAD: Secrets in database seeds
User.create!(api_key: "real-production-key")
```

### Content Security Policy

```ruby
# config/initializers/content_security_policy.rb
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, "https://fonts.googleapis.com"
    policy.img_src     :self, :data, "https://gravatar.com"
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline  # Required for some frameworks
    policy.connect_src :self
  end

  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
```

### Rate Limiting (Rails 8+)

```ruby
class Api::V1::AiController < Api::V1::BaseController
  rate_limit to: 20, within: 1.minute, by: -> { current_user.id }, with: -> {
    render json: { error: "Rate limited. Try again in a moment." }, status: :too_many_requests
  }
end
```

## Security Checklist

Every Rails app should verify:

- [ ] Strong parameters on every controller action
- [ ] No string interpolation in SQL queries
- [ ] No `raw` or `html_safe` on user input
- [ ] CSRF protection enabled for web controllers
- [ ] API authentication via tokens (not cookies)
- [ ] All queries scoped to `current_user` (no IDOR)
- [ ] Secrets in credentials or ENV, never in code
- [ ] `force_ssl` enabled in production
- [ ] Dependencies updated regularly (`bundle audit`)
- [ ] Rate limiting on expensive endpoints
- [ ] CSP headers configured
