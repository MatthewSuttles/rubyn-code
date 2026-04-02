# Code Quality: Naming Conventions

## Pattern

Good names are the cheapest documentation. A well-named method, class, or variable eliminates the need for comments and makes code read like prose. Ruby and Rails have strong naming conventions — follow them.

### Ruby Naming Rules

```ruby
# Classes and modules: CamelCase (PascalCase)
class OrderProcessor; end
module Authenticatable; end
class Api::V1::OrdersController; end

# Methods and variables: snake_case
def calculate_total; end
total_cents = 19_99
current_user = User.find(session[:user_id])

# Constants: SCREAMING_SNAKE_CASE
MAX_RETRIES = 3
DEFAULT_CURRENCY = "USD"
API_BASE_URL = "https://api.rubyn.ai"

# Predicates (boolean methods): end with ?
def active?; end
def can_cancel?; end
def shipped?; end
# Returns true/false. Never name it `is_active` or `check_active`.

# Dangerous methods: end with !
def save!; end       # Raises on failure (vs save which returns false)
def destroy!; end    # Raises on failure
def normalize!; end  # Mutates in place (vs normalize which returns new value)
# ! means "this version does something surprising" — usually raises or mutates.

# Setters: end with =
def name=(value); end
attr_writer :name    # Generates name= method

# Private/internal: prefix with _ (convention, not enforced)
def _build_cache_key; end
_temp_value = compute_intermediate_step
```

### Method Naming

```ruby
# GOOD: Verb for actions, noun for queries
def create_order(params); end       # Action: does something
def send_confirmation(order); end   # Action: does something
def total; end                      # Query: returns a value
def line_items; end                 # Query: returns a collection
def pending?; end                   # Predicate: returns boolean

# GOOD: Specific verbs that communicate intent
def charge_payment(order); end      # Specific: charges
def validate_inventory(items); end  # Specific: validates
def generate_reference; end         # Specific: generates

# BAD: Vague verbs that could mean anything
def process(order); end             # Process how? Does it charge? Ship? Validate?
def handle(data); end               # Handle what exactly?
def do_stuff; end                   # Meaningless
def run; end                        # What does it run?
def execute; end                    # Same problem

# GOOD: call for service objects (convention)
class Orders::CreateService
  def self.call(params, user); end  # .call is the Rails service object convention
end
# This works because the CLASS NAME describes the action (CreateService)
# so .call doesn't need to be more specific

# GOOD: Named constructors for clarity
Order.from_cart(cart, user: current_user)
Money.from_dollars(19.99)
DateRange.parse("2026-01-01..2026-03-20")
```

### Class Naming

```ruby
# GOOD: Noun describing what it IS
class Order; end
class LineItem; end
class User; end

# GOOD: Adjective or role for modules (describes capability)
module Searchable; end
module Authenticatable; end
module Sluggable; end

# GOOD: Noun + purpose for service objects
class Orders::CreateService; end
class Credits::DeductionService; end
class Embeddings::CodebaseIndexer; end

# GOOD: Noun + type for specific patterns
class OrderPresenter; end           # Presenter
class RegistrationForm; end         # Form object
class OrdersSearchQuery; end        # Query object
class StripeAdapter; end            # Adapter
class EmailNotifier; end            # Notifier

# BAD: Manager, Handler, Processor, Helper (vague — WHAT does it manage?)
class OrderManager; end             # What aspect of orders?
class DataHandler; end              # What data? What handling?
class OrderProcessor; end           # Processes how?
class OrderHelper; end              # Helps with what?

# FIX: Name the specific responsibility
class OrderManager → Orders::CreateService + Orders::CancelService
class DataHandler → CsvImporter + JsonParser
class OrderProcessor → Orders::FulfillmentService
```

### Variable Naming

```ruby
# GOOD: Descriptive, matches the domain
active_users = User.where(active: true)
pending_orders = Order.pending
credit_balance = user.credit_ledger_entries.sum(:amount)
shipping_address = order.addresses.find_by(type: "shipping")

# GOOD: Plural for collections, singular for individuals
orders = Order.recent           # Collection
order = orders.first            # Single item
line_items = order.line_items   # Collection
line_item = line_items.first    # Single item

# BAD: Single-letter variables (except in tiny blocks)
u = User.find(params[:id])     # What's u? 
o = u.orders.last              # What's o?
x = o.total * 0.08             # What's x?

# OK: Single-letter in small, obvious blocks
users.map { |u| u.email }      # OK — the block is 1 line, u is clearly a user
users.map(&:email)              # BETTER — no variable needed

# BAD: Misleading names
user_count = User.pluck(:email)        # It's emails, not a count
is_valid = order.save                  # It's a save result, not a validation check
temp = Order.where(status: :pending)   # "temp" tells you nothing

# BAD: Hungarian notation or type prefixes
str_name = "Alice"                     # Ruby doesn't need type prefixes
arr_items = [1, 2, 3]
int_count = 5
hash_config = { timeout: 30 }
```

### Rails-Specific Conventions

```ruby
# Controllers: plural noun + Controller
class OrdersController; end           # Not OrderController
class Api::V1::UsersController; end

# Models: singular noun
class Order; end                      # Not Orders
class LineItem; end                   # Not LineItems

# Tables: plural snake_case (matches model pluralized)
# orders, line_items, users, credit_ledger_entries

# Foreign keys: singular_model_id
# order_id, user_id, product_id

# Join tables: alphabetical, both pluralized
# orders_products, categories_products

# Migrations: verb + noun
class AddStatusToOrders; end
class CreateProjectMemberships; end
class RemoveDeletedAtFromOrders; end

# Jobs: noun + Job
class OrderConfirmationJob; end
class CodebaseIndexJob; end

# Mailers: noun + Mailer
class OrderMailer; end
class UserMailer; end

# Serializers: singular model + Serializer
class OrderSerializer; end

# Factories: plural snake_case (matching table)
# spec/factories/orders.rb
# spec/factories/line_items.rb
```

## Why This Is Good

- **Convention eliminates decisions.** When every controller is `PluralNounController` and every service is `Noun::VerbService`, developers don't waste time choosing names. The convention chooses for them.
- **Names replace comments.** `calculate_shipping_cost` doesn't need a comment explaining what it does. `process` does.
- **Predictable file locations.** `Orders::CreateService` lives at `app/services/orders/create_service.rb`. The name maps to the path. You can find any class without grep.
- **`?` and `!` suffixes communicate behavior.** `save` returns false on failure. `save!` raises. The developer knows what to expect from the suffix alone.

## The Rename Test

If you can't think of a good name for a method or class, it probably does too many things. A method that does one thing always has a clear name.

- ❌ `process_order` → What processing? Creating? Shipping? Billing? All three?
- ✅ `Orders::CreateService`, `Orders::ShipService`, `Orders::BillService`

- ❌ `handle_response` → Handle how?
- ✅ `parse_json_response`, `validate_response_status`, `extract_order_from_response`

- ❌ `UserManager` → Manages what about users?
- ✅ `Users::RegistrationService`, `Users::ProfileUpdater`, `Users::DeactivationService`
