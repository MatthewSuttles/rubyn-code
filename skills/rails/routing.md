# Rails: Routing

## Pattern

Routes define your application's public API surface. Keep them RESTful, use resources for CRUD, create new controllers instead of custom actions, and use namespaces to organize related endpoints.

### RESTful Resources

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # GOOD: Standard RESTful resources
  resources :orders, only: [:index, :show, :create, :update, :destroy]
  resources :products, only: [:index, :show]

  # GOOD: Nested resources for parent-child relationships
  resources :orders do
    resources :line_items, only: [:create, :destroy]
    resource :shipment, only: [:show, :create]  # singular — one shipment per order
  end
  # Generates: /orders/:order_id/line_items
  #            /orders/:order_id/shipment

  # GOOD: Shallow nesting — child resources get their own top-level routes for show/edit/destroy
  resources :projects, shallow: true do
    resources :memberships, only: [:index, :create, :show, :destroy]
  end
  # Generates: /projects/:project_id/memberships     (index, create)
  #            /memberships/:id                        (show, destroy)
end
```

### New Controllers Over Custom Actions

```ruby
# BAD: Custom actions on a resource controller
resources :orders do
  member do
    post :cancel        # POST /orders/:id/cancel
    post :ship          # POST /orders/:id/ship
    post :refund        # POST /orders/:id/refund
    get :invoice        # GET /orders/:id/invoice
    get :tracking       # GET /orders/:id/tracking
  end
end

# GOOD: Each verb gets its own resource controller
resources :orders, only: [:index, :show, :create, :update] do
  resource :cancellation, only: [:create], controller: "order_cancellations"
  resource :shipment, only: [:show, :create], controller: "order_shipments"
  resource :refund, only: [:create], controller: "order_refunds"
  resource :invoice, only: [:show], controller: "order_invoices"
  resource :tracking, only: [:show], controller: "order_trackings"
end
```

Each new controller has a single RESTful action. `OrderCancellationsController#create` is clearer than `OrdersController#cancel`, and each controller stays skinny.

### Namespaces, Scopes, and Modules

```ruby
Rails.application.routes.draw do
  # namespace: adds URL prefix AND module prefix
  namespace :admin do
    resources :users          # Admin::UsersController, /admin/users
    resources :orders         # Admin::OrdersController, /admin/orders
    root to: "dashboard#show"
  end

  # namespace for API versioning
  namespace :api do
    namespace :v1 do
      resources :orders       # Api::V1::OrdersController, /api/v1/orders
      resources :projects do
        resources :embeddings, only: [:index, :create]
      end
      namespace :ai do
        post :refactor        # Api::V1::Ai::RefactorController (if using Grape, mount instead)
        post :review
        post :spec
      end
    end
  end

  # scope: adds URL prefix but NOT module prefix
  scope "/dashboard" do
    resources :analytics, only: [:index]  # AnalyticsController, /dashboard/analytics
  end

  # module: adds module prefix but NOT URL prefix
  scope module: :public do
    resources :products, only: [:index, :show]  # Public::ProductsController, /products
  end
end
```

### Constraints and Advanced Routing

```ruby
Rails.application.routes.draw do
  # Subdomain constraints
  constraints subdomain: "api" do
    namespace :api, path: "" do  # api.rubyn.ai/v1/orders instead of api.rubyn.ai/api/v1/orders
      namespace :v1 do
        resources :orders
      end
    end
  end

  # Format constraints
  resources :reports, only: [:show], defaults: { format: :json }

  # Custom constraints
  constraints ->(req) { req.env["HTTP_AUTHORIZATION"].present? } do
    resources :admin_tools
  end

  # Catch-all for SPA (must be LAST)
  get "*path", to: "application#frontend", constraints: ->(req) { !req.xhr? && req.format.html? }
end
```

### Route Helpers and Path Generation

```ruby
# Use named routes — never hardcode paths
redirect_to order_path(@order)              # /orders/123
redirect_to order_line_items_path(@order)    # /orders/123/line_items
redirect_to [:admin, @user]                  # /admin/users/456
redirect_to new_order_path                   # /orders/new

# Polymorphic routing
redirect_to [@order, @line_item]             # /orders/123/line_items/789

# URL helpers in non-controller contexts
Rails.application.routes.url_helpers.order_url(order, host: "rubyn.ai")
```

## Why This Is Good

- **RESTful resources are predictable.** Any Rails developer opening your routes file knows that `resources :orders` means 7 standard actions. Custom actions require reading each one.
- **New controllers keep actions skinny.** `OrderCancellationsController#create` has one job. `OrdersController#cancel` is a non-RESTful action hiding in a RESTful controller.
- **Namespaces organize by concern.** Admin routes, API routes, and public routes are clearly separated. Different authentication, different base controllers, different middleware.
- **Shallow nesting avoids deep URLs.** `/projects/1/memberships/2/permissions/3` is painful. Shallow nesting gives children their own top-level routes after creation.
- **`only:` keeps it explicit.** `resources :products, only: [:index, :show]` tells you exactly which endpoints exist. No guessing, no unused routes.

## Anti-Pattern

```ruby
# BAD: Everything on one controller, no nesting discipline
resources :orders do
  collection do
    get :search
    get :export
    get :report
  end
  member do
    post :cancel
    post :ship
    post :approve
    post :reject
    post :archive
    post :duplicate
    get :pdf
    get :receipt
  end
end
# OrdersController now has 15+ actions
```

## When To Apply

- **Every Rails app.** RESTful routing is the Rails way. It's not optional.
- **When an action doesn't map to CRUD** — it's a new controller, not a custom action. "Cancel" is creating a cancellation. "Ship" is creating a shipment.
- **API versioning from day one.** `/api/v1/` costs nothing now and saves everything later.
- **`only:` on every `resources` call.** Don't generate routes you don't use.

## When NOT To Apply

- **Sinatra apps.** Sinatra routes are explicit — no `resources` macro. Just define the routes you need.
- **Single-action controllers don't need resources.** A health check is `get "/health", to: "health#show"`, not `resources :health`.
- **Don't over-nest.** Never go deeper than 2 levels. `/orders/:id/line_items` is fine. `/companies/:id/orders/:id/line_items/:id/adjustments` is too deep — use shallow nesting or flatten.

## Edge Cases

**Mounting engines and Rack apps:**

```ruby
mount Rubyn::Engine => "/rubyn" if Rails.env.development?
mount Sidekiq::Web => "/sidekiq" if Rails.env.development?
mount ActionCable.server => "/cable"
```

**Route precedence:** Routes are matched top to bottom. Put specific routes before generic ones, and catch-all routes last.
