# Rails: Query Objects

## Pattern

Extract complex database queries into query objects when a scope chain becomes long, requires conditional logic, or involves joins and subqueries that obscure intent. Query objects live in `app/queries/` and return ActiveRecord relations so they remain chainable.

```ruby
# app/queries/orders/search_query.rb
module Orders
  class SearchQuery
    def self.call(params)
      new(params).call
    end

    def initialize(params)
      @params = params
    end

    def call
      scope = Order.includes(:user, :line_items)
      scope = filter_by_status(scope)
      scope = filter_by_date_range(scope)
      scope = filter_by_total(scope)
      scope = search_by_keyword(scope)
      scope = apply_sorting(scope)
      scope
    end

    private

    def filter_by_status(scope)
      return scope unless @params[:status].present?

      scope.where(status: @params[:status])
    end

    def filter_by_date_range(scope)
      scope = scope.where(created_at: @params[:from]..) if @params[:from].present?
      scope = scope.where(created_at: ..@params[:to]) if @params[:to].present?
      scope
    end

    def filter_by_total(scope)
      scope = scope.where("total >= ?", @params[:min_total]) if @params[:min_total].present?
      scope = scope.where("total <= ?", @params[:max_total]) if @params[:max_total].present?
      scope
    end

    def search_by_keyword(scope)
      return scope unless @params[:q].present?

      scope.where("orders.reference ILIKE :q OR users.email ILIKE :q", q: "%#{@params[:q]}%")
           .references(:user)
    end

    def apply_sorting(scope)
      case @params[:sort]
      when "newest" then scope.order(created_at: :desc)
      when "oldest" then scope.order(created_at: :asc)
      when "highest" then scope.order(total: :desc)
      else scope.order(created_at: :desc)
      end
    end
  end
end
```

The controller stays minimal:

```ruby
class OrdersController < ApplicationController
  def index
    @orders = Orders::SearchQuery.call(search_params).page(params[:page])
  end

  private

  def search_params
    params.permit(:status, :from, :to, :min_total, :max_total, :q, :sort)
  end
end
```

## Why This Is Good

- **Returns a relation.** The query object returns an ActiveRecord::Relation, not an array. You can chain `.page()`, `.limit()`, `.count()` on the result. It composes with the rest of Rails.
- **Each filter is isolated.** Adding a new filter means adding one private method. Removing a filter means removing one method. No risk of breaking other filters.
- **Testable without HTTP.** Pass in a params hash, assert the SQL or the returned records. Fast, focused tests.
- **Reusable.** The same query object works in the controller, in an API endpoint, in a CSV export job, and in an admin panel.
- **Readable intent.** `Orders::SearchQuery.call(params)` communicates what's happening. A 30-line scope chain in a controller does not.

## Anti-Pattern

Building complex queries inline in the controller with conditional scope chaining:

```ruby
class OrdersController < ApplicationController
  def index
    @orders = Order.includes(:user, :line_items)

    if params[:status].present?
      @orders = @orders.where(status: params[:status])
    end

    if params[:from].present?
      @orders = @orders.where("created_at >= ?", params[:from])
    end

    if params[:to].present?
      @orders = @orders.where("created_at <= ?", params[:to])
    end

    if params[:min_total].present?
      @orders = @orders.where("total >= ?", params[:min_total])
    end

    if params[:q].present?
      @orders = @orders.joins(:user)
                       .where("orders.reference ILIKE :q OR users.email ILIKE :q", q: "%#{params[:q]}%")
    end

    @orders = case params[:sort]
              when "newest" then @orders.order(created_at: :desc)
              when "oldest" then @orders.order(created_at: :asc)
              when "highest" then @orders.order(total: :desc)
              else @orders.order(created_at: :desc)
              end

    @orders = @orders.page(params[:page])
  end
end
```

## Why This Is Bad

- **30+ lines of query logic in a controller.** The controller's job is HTTP handling, not query construction.
- **Impossible to reuse.** When the admin panel needs the same search, you copy-paste the entire block. When the API needs it, you copy it again. When the logic changes, you update it in three places.
- **Difficult to test.** Testing this requires making HTTP requests and asserting HTML or JSON output. You can't test the query logic in isolation.
- **Grows unbounded.** Every new filter adds another `if` block. Every new sort option adds a `when` clause. The controller action becomes the longest method in the codebase.

## When To Apply

Use a query object when ANY of these are true:

- A query has **3 or more conditional filters** (status, date range, keyword, price range)
- The query involves **joins, subqueries, or raw SQL fragments** that obscure what's being queried
- The **same query logic is needed in multiple places** (web controller, API, admin, background job, export)
- The query is used for **reporting or analytics** (monthly revenue, user activity, conversion funnels)
- A model's scope chain is getting **longer than 3 chained scopes** for a single use case

## When NOT To Apply

- **Simple, reusable filters belong as scopes on the model.** `Order.recent`, `Order.pending`, `Order.for_user(user)` are fine as scopes. They're short, reusable, and chainable.
- **Single-condition queries don't need a class.** `Order.where(status: :pending)` in a controller is perfectly fine. Don't extract a query object for one `where` clause.
- The query is **only used in one place** and is **under 5 lines.** A small inline query in a controller is more readable than navigating to a separate file.

## Edge Cases

**Some filters should always be applied (like tenant scoping):**
Apply those in the constructor or at the top of `call`, not as conditional filters. Tenant scoping is not optional.

```ruby
def call
  scope = Order.where(company: @company) # Always applied
  scope = filter_by_status(scope)        # Conditionally applied
  scope
end
```

**The query needs to return raw data (not ActiveRecord objects):**
Use `.pluck`, `.select`, or `.to_sql` at the call site, not inside the query object. The query object returns a relation; the caller decides how to materialize it.

**You need both a count and the results:**
Return the relation. The caller chains `.count` or `.to_a` as needed. Don't build two methods that run nearly identical queries.

**The query is extremely complex (CTEs, window functions):**
Consider `Arel` for type-safe query construction, or use `.from(Arel.sql(...))` for raw SQL. Wrap it in the query object so the complexity is contained in one place. Add comments explaining the SQL.
