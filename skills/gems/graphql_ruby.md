# Gem: graphql-ruby

## What It Is

The `graphql` gem (graphql-ruby) is the standard Ruby implementation of GraphQL. It provides a type system, schema definition, query execution, mutations, subscriptions, and tooling for building GraphQL APIs in Rails. It's powerful but has a steep learning curve and many subtle gotchas.

## Setup Done Right

```ruby
# Gemfile
gem 'graphql'

# Generate the schema
rails generate graphql:install

# This creates:
# app/graphql/your_app_schema.rb
# app/graphql/types/query_type.rb
# app/graphql/types/mutation_type.rb
# app/graphql/types/base_*.rb
# app/controllers/graphql_controller.rb
```

```ruby
# app/graphql/rubyn_schema.rb
class RubynSchema < GraphQL::Schema
  query Types::QueryType
  mutation Types::MutationType

  # IMPORTANT: Set max complexity and depth to prevent abuse
  max_complexity 300
  max_depth 15
  default_max_page_size 25

  # Use dataloader for N+1 prevention (replaces batch-loader gems)
  use GraphQL::Dataloader

  # Error handling
  rescue_from(ActiveRecord::RecordNotFound) do |err, obj, args, ctx, field|
    raise GraphQL::ExecutionError, "#{field.type.unwrap.graphql_name} not found"
  end

  rescue_from(Pundit::NotAuthorizedError) do |err, obj, args, ctx, field|
    raise GraphQL::ExecutionError, "Not authorized"
  end
end
```

## Gotcha #1: N+1 Queries Are Silent and Devastating

GraphQL's nested structure naturally creates N+1 queries. A query for 25 orders with their users and line items can generate 75+ queries if you're not careful.

```graphql
# This innocent query causes N+1 hell
{
  orders(first: 25) {
    nodes {
      id
      total
      user {         # N queries for users
        name
        email
      }
      lineItems {    # N queries for line items
        product {    # N*M queries for products
          name
        }
      }
    }
  }
}
```

**WRONG: Direct association access in type resolvers**

```ruby
# app/graphql/types/order_type.rb
class Types::OrderType < Types::BaseObject
  field :user, Types::UserType, null: false
  field :line_items, [Types::LineItemType], null: false

  # These default resolvers call order.user and order.line_items
  # Each call is a separate query — N+1!
end
```

**RIGHT: Use GraphQL::Dataloader (built-in since graphql-ruby 2.0)**

```ruby
# app/graphql/sources/record_source.rb
class Sources::RecordSource < GraphQL::Dataloader::Source
  def initialize(model_class, column: :id)
    @model_class = model_class
    @column = column
  end

  def fetch(ids)
    records = @model_class.where(@column => ids)
    ids.map { |id| records.find { |r| r.public_send(@column) == id } }
  end
end

# app/graphql/sources/association_source.rb
class Sources::AssociationSource < GraphQL::Dataloader::Source
  def initialize(model_class, association_name)
    @model_class = model_class
    @association_name = association_name
  end

  def fetch(records)
    ActiveRecord::Associations::Preloader.new(
      records: records,
      associations: @association_name
    ).call

    records.map { |record| record.public_send(@association_name) }
  end
end

# app/graphql/types/order_type.rb
class Types::OrderType < Types::BaseObject
  field :user, Types::UserType, null: false
  field :line_items, [Types::LineItemType], null: false

  def user
    dataloader.with(Sources::RecordSource, User).load(object.user_id)
  end

  def line_items
    dataloader.with(Sources::AssociationSource, Order, :line_items).load(object)
  end
end
```

**The trap:** Everything works in development with 5 records. In production with 25 records per page, the query takes 3 seconds and makes 200 database calls. Always check your query count with `bullet` or query logs.

## Gotcha #2: Authorization — Don't Trust the Client

GraphQL clients can query any field in the schema. Authorization must happen at the field/type level, not just at the query root.

```ruby
# WRONG: Only checking auth at the query root
class Types::QueryType < Types::BaseObject
  field :orders, Types::OrderType.connection_type, null: false

  def orders
    # Checks that user is logged in... but returns ALL orders
    raise GraphQL::ExecutionError, "Not authenticated" unless context[:current_user]
    Order.all  # SECURITY HOLE: User sees everyone's orders
  end
end

# RIGHT: Scope queries AND authorize individual records
class Types::QueryType < Types::BaseObject
  field :orders, Types::OrderType.connection_type, null: false

  def orders
    raise GraphQL::ExecutionError, "Not authenticated" unless context[:current_user]
    OrderPolicy::Scope.new(context[:current_user], Order).resolve.order(created_at: :desc)
  end
end

# RIGHT: Authorize field-level access for sensitive fields
class Types::UserType < Types::BaseObject
  field :email, String, null: false
  field :credit_balance, Integer, null: false

  # Only show email to the user themselves or admins
  def email
    if context[:current_user] == object || context[:current_user]&.admin?
      object.email
    else
      raise GraphQL::ExecutionError, "Not authorized to view email"
    end
  end

  # Only show credit balance to the user themselves
  def credit_balance
    raise GraphQL::ExecutionError, "Not authorized" unless context[:current_user] == object
    object.credit_balance
  end
end
```

**The trap:** A user queries `{ users { email creditBalance } }` and sees everyone's email and credit balance. Field-level auth is essential because clients control which fields they request.

## Gotcha #3: Context Setup in the Controller

The `context` hash is your bridge between Rails and GraphQL. Set it up once, use it everywhere.

```ruby
# app/controllers/graphql_controller.rb
class GraphqlController < ApplicationController
  skip_before_action :verify_authenticity_token  # API endpoint, not a form

  def execute
    result = RubynSchema.execute(
      params[:query],
      variables: prepare_variables(params[:variables]),
      context: {
        current_user: current_user,        # From Devise or your auth
        request: request,                   # For IP, user agent
        pundit_user: current_user           # If using Pundit integration
      },
      operation_name: params[:operationName]
    )
    render json: result
  rescue StandardError => e
    handle_error(e)
  end

  private

  def prepare_variables(variables_param)
    case variables_param
    when String then variables_param.present? ? JSON.parse(variables_param) : {}
    when Hash then variables_param
    when ActionController::Parameters then variables_param.to_unsafe_hash
    when nil then {}
    else raise ArgumentError, "Unexpected variables: #{variables_param}"
    end
  end

  def handle_error(e)
    Rails.logger.error("GraphQL Error: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { errors: [{ message: "Internal server error" }] }, status: :internal_server_error
  end
end
```

**The trap:** `params[:variables]` can be a String (from a POST body), a Hash (from a JSON body), or ActionController::Parameters (from Rails). If you don't handle all three, queries with variables break intermittently depending on the client library.

## Gotcha #4: Mutations — Input Types and Error Handling

```ruby
# WRONG: Returning generic error strings
class Mutations::CreateOrder < Mutations::BaseMutation
  argument :shipping_address, String, required: true

  field :order, Types::OrderType, null: true

  def resolve(shipping_address:)
    order = context[:current_user].orders.create!(shipping_address: shipping_address)
    { order: order }
  rescue ActiveRecord::RecordInvalid => e
    raise GraphQL::ExecutionError, e.message  # Lumps all errors into one string
  end
end
```

```ruby
# RIGHT: Structured error responses with field-level errors
class Mutations::CreateOrder < Mutations::BaseMutation
  argument :shipping_address, String, required: true
  argument :note, String, required: false

  field :order, Types::OrderType, null: true
  field :errors, [Types::UserErrorType], null: false

  def resolve(shipping_address:, note: nil)
    authorize_action!

    order = context[:current_user].orders.build(
      shipping_address: shipping_address,
      note: note
    )

    if order.save
      { order: order, errors: [] }
    else
      {
        order: nil,
        errors: order.errors.map { |e|
          { field: e.attribute.to_s.camelize(:lower), message: e.full_message }
        }
      }
    end
  end

  private

  def authorize_action!
    raise GraphQL::ExecutionError, "Not authenticated" unless context[:current_user]
    raise GraphQL::ExecutionError, "Insufficient credits" unless context[:current_user].credit_balance > 0
  end
end

# app/graphql/types/user_error_type.rb
class Types::UserErrorType < Types::BaseObject
  field :field, String, null: true, description: "Which input field the error relates to"
  field :message, String, null: false, description: "Human-readable error message"
end
```

**The trap:** `GraphQL::ExecutionError` puts errors in the top-level `errors` array, which clients typically treat as unexpected failures. Validation errors should be in the `data` response as structured fields, so the client can display them next to form fields.

## Gotcha #5: Connection Types and Pagination

```ruby
# WRONG: Returning a plain array — no pagination
field :orders, [Types::OrderType], null: false
def orders
  Order.all  # Loads every order into memory
end

# RIGHT: Use connection types for automatic cursor-based pagination
field :orders, Types::OrderType.connection_type, null: false

def orders
  policy_scope(Order).order(created_at: :desc)
  # GraphQL handles first/last/before/after automatically
end
```

```graphql
# Client gets pagination for free
{
  orders(first: 10, after: "MjA=") {
    edges {
      node {
        id
        total
      }
      cursor
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

**The trap:** Without connection types, requesting 10,000 orders loads them all. Connection types enforce pagination and provide cursor-based navigation. Set `default_max_page_size` in your schema.

## Gotcha #6: Enum Types Must Match Exactly

```ruby
# WRONG: String values that don't match DB enum
class Types::OrderStatusEnum < Types::BaseEnum
  value "PENDING"     # GraphQL convention is SCREAMING_SNAKE
  value "CONFIRMED"
  value "SHIPPED"
end

# But the DB stores "pending", "confirmed", "shipped"
# This silently doesn't match — filters return no results
```

```ruby
# RIGHT: Map GraphQL values to DB values
class Types::OrderStatusEnum < Types::BaseEnum
  value "PENDING", value: "pending"
  value "CONFIRMED", value: "confirmed"
  value "SHIPPED", value: "shipped"
  value "DELIVERED", value: "delivered"
  value "CANCELLED", value: "cancelled"
end

# Usage in a query argument
field :orders, Types::OrderType.connection_type, null: false do
  argument :status, Types::OrderStatusEnum, required: false
end

def orders(status: nil)
  scope = policy_scope(Order)
  scope = scope.where(status: status) if status  # status is now "pending", not "PENDING"
  scope.order(created_at: :desc)
end
```

## Gotcha #7: Circular Type References

Types that reference each other (User has Orders, Order has User) can cause load-order issues.

```ruby
# This can cause "uninitialized constant Types::OrderType" if load order is wrong
class Types::UserType < Types::BaseObject
  field :orders, [Types::OrderType], null: false  # OrderType may not be loaded yet
end

# FIX: Use a string or lambda for lazy resolution
class Types::UserType < Types::BaseObject
  field :orders, [Types::OrderType], null: false
  # graphql-ruby handles circular references automatically in modern versions
  # But if you get load errors, use:
  field :orders, ["Types::OrderType"], null: false  # String reference, resolved lazily
end
```

## Gotcha #8: Testing GraphQL

```ruby
# spec/support/graphql_helpers.rb
module GraphqlHelpers
  def execute_query(query, variables: {}, user: nil)
    RubynSchema.execute(
      query,
      variables: variables,
      context: { current_user: user }
    )
  end

  def graphql_data(result)
    result["data"]
  end

  def graphql_errors(result)
    result["errors"]
  end
end

RSpec.configure do |config|
  config.include GraphqlHelpers, type: :graphql
end
```

```ruby
# spec/graphql/queries/orders_query_spec.rb
RSpec.describe "orders query", type: :graphql do
  let(:user) { create(:user) }
  let!(:orders) { create_list(:order, 3, user: user) }
  let!(:other_order) { create(:order) }

  let(:query) do
    <<~GQL
      query($first: Int) {
        orders(first: $first) {
          nodes {
            id
            total
          }
        }
      }
    GQL
  end

  it "returns only the user's orders" do
    result = execute_query(query, variables: { first: 10 }, user: user)

    expect(graphql_errors(result)).to be_nil
    nodes = graphql_data(result).dig("orders", "nodes")
    expect(nodes.length).to eq(3)
  end

  it "requires authentication" do
    result = execute_query(query, user: nil)
    expect(graphql_errors(result).first["message"]).to include("Not authenticated")
  end
end
```

```ruby
# spec/graphql/mutations/create_order_mutation_spec.rb
RSpec.describe "createOrder mutation", type: :graphql do
  let(:user) { create(:user, credit_balance: 100) }

  let(:mutation) do
    <<~GQL
      mutation($input: CreateOrderInput!) {
        createOrder(input: $input) {
          order {
            id
            shippingAddress
          }
          errors {
            field
            message
          }
        }
      }
    GQL
  end

  it "creates an order" do
    result = execute_query(mutation, variables: {
      input: { shippingAddress: "123 Main St" }
    }, user: user)

    data = graphql_data(result)["createOrder"]
    expect(data["errors"]).to be_empty
    expect(data["order"]["shippingAddress"]).to eq("123 Main St")
  end

  it "returns validation errors" do
    result = execute_query(mutation, variables: {
      input: { shippingAddress: "" }
    }, user: user)

    data = graphql_data(result)["createOrder"]
    expect(data["order"]).to be_nil
    expect(data["errors"].first["field"]).to eq("shippingAddress")
  end
end
```

## Do's and Don'ts Summary

**DO:**
- Use `GraphQL::Dataloader` for every association — N+1 is the default without it
- Set `max_complexity`, `max_depth`, and `default_max_page_size` to prevent abuse
- Use connection types for all list fields
- Return structured errors from mutations (not just `GraphQL::ExecutionError`)
- Authorize at field level, not just query level
- Handle all `variables` formats in the controller (String, Hash, ActionController::Parameters)

**DON'T:**
- Don't return plain arrays — use connection types for pagination
- Don't trust that clients only request authorized fields — enforce it server-side
- Don't use `GraphQL::ExecutionError` for validation errors — use structured error fields
- Don't forget `skip_before_action :verify_authenticity_token` on the GraphQL controller
- Don't define enum values without mapping to DB values
- Don't load records without scoping to the current user first
- Don't put business logic in resolvers — delegate to service objects
