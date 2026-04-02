# Rails: Engines

## Pattern

A Rails engine is a miniature Rails application that can be mounted inside a host app. Engines package controllers, models, views, routes, and assets into a self-contained, reusable component. Use them for features that are isolated from the host app's domain — admin panels, dev tools, billing dashboards, and embeddable widgets.

```ruby
# Generate a mountable engine
# rails plugin new rubyn --mountable

# lib/rubyn/engine.rb
module Rubyn
  class Engine < ::Rails::Engine
    isolate_namespace Rubyn

    # Engine-specific configuration
    config.generators do |g|
      g.test_framework :rspec
      g.assets false  # Engine manages its own assets
    end

    # Initializers run when the host app boots
    initializer "rubyn.assets" do |app|
      app.config.assets.precompile += %w[rubyn/application.css rubyn/application.js] if app.config.respond_to?(:assets)
    end
  end
end
```

```ruby
# Engine routes — completely isolated from host app
# config/routes.rb (inside the engine)
Rubyn::Engine.routes.draw do
  root to: "dashboard#show"

  resources :files, only: [:index, :show]
  resource :agent, only: [:show, :create]

  namespace :ai do
    post :refactor
    post :review
    post :spec
  end

  resource :settings, only: [:show, :update]
end
```

```ruby
# Host app mounts the engine
# config/routes.rb (host app)
Rails.application.routes.draw do
  mount Rubyn::Engine => "/rubyn" if Rails.env.development?

  # Host app's own routes
  resources :orders
end
```

### Engine Controllers

```ruby
# app/controllers/rubyn/application_controller.rb
module Rubyn
  class ApplicationController < ActionController::Base
    layout "rubyn/application"  # Engine's own layout

    before_action :verify_development_environment

    private

    def verify_development_environment
      head :forbidden unless Rails.env.development?
    end

    # Engine reads credentials from the user's local config
    def rubyn_api_key
      @rubyn_api_key ||= Rubyn::Config.api_key
    end
  end
end

# app/controllers/rubyn/dashboard_controller.rb
module Rubyn
  class DashboardController < ApplicationController
    def show
      @project_info = Rubyn::ProjectScanner.scan(Rails.root)
      @credit_balance = Rubyn::ApiClient.new(rubyn_api_key).balance
      @recent_activity = Rubyn::ApiClient.new(rubyn_api_key).recent_interactions(limit: 10)
    end
  end
end
```

### Engine Views (Self-Contained)

```erb
<%# app/views/layouts/rubyn/application.html.erb %>
<%# Engine has its own layout — doesn't depend on host app's layout %>
<!DOCTYPE html>
<html>
<head>
  <title>Rubyn</title>
  <%= csrf_meta_tags %>
  <%= stylesheet_link_tag "rubyn/application", media: "all" %>
</head>
<body class="rubyn-app">
  <nav class="rubyn-nav">
    <%= link_to "Dashboard", rubyn.root_path %>
    <%= link_to "Files", rubyn.files_path %>
    <%= link_to "Agent", rubyn.agent_path %>
    <%= link_to "Settings", rubyn.settings_path %>
  </nav>

  <main>
    <%= yield %>
  </main>

  <%= javascript_include_tag "rubyn/application" %>
</body>
</html>
```

### Namespace Isolation

```ruby
# isolate_namespace ensures the engine doesn't pollute the host app

# Engine model — lives in rubyn_ prefixed tables
module Rubyn
  class Interaction < ApplicationRecord
    # Table: rubyn_interactions (not interactions)
  end
end

# Engine routes are namespaced
rubyn.root_path        # => "/rubyn"
rubyn.files_path       # => "/rubyn/files"
main_app.orders_path   # => "/orders" (host app routes)

# In engine views, explicitly reference host vs engine routes:
<%= link_to "Back to app", main_app.root_path %>
<%= link_to "Dashboard", rubyn.root_path %>
```

## Why This Is Good

- **Complete isolation.** The engine has its own namespace, routes, views, assets, and optionally its own database tables. It can't accidentally conflict with the host app's controllers or styles.
- **Mountable with one line.** `mount Rubyn::Engine => "/rubyn"` — the host app adds one line and gets a full-featured dev dashboard.
- **Development-only by default.** `if Rails.env.development?` ensures the engine never accidentally runs in production.
- **Self-contained assets.** The engine ships its own CSS and JavaScript. No dependency on the host app's Tailwind config, asset pipeline, or build tools.
- **Shareable across projects.** Package the engine as a gem, install it in any Rails project, mount it — instant dev tools.

## When To Apply

- **Dev tools** — dashboards, profilers, debug panels, AI coding assistants. Features that help developers but shouldn't exist in production.
- **Admin panels** — self-contained admin interfaces with their own auth, layout, and styles.
- **Shared features across apps** — authentication, billing, notifications, CMS. Build once, mount in multiple apps.
- **Rubyn itself** — the mountable web UI is an engine inside the `rubyn` gem.

## When NOT To Apply

- **Feature that's tightly coupled to the host app's domain.** If the feature needs to share models, validations, and business logic with the host app, it's not a good engine candidate — it's just part of the app.
- **Simple shared code.** A few utility methods shared across apps should be a gem with modules, not an engine with controllers and views.
- **One-off features.** Don't engine-ify something used in only one app. Engines add architectural overhead.

## Edge Cases

**Engine accessing host app's models:**
```ruby
# The engine can reference host app models if they exist
class Rubyn::DashboardController < Rubyn::ApplicationController
  def show
    # Access host app's models — works but creates coupling
    @user_count = ::User.count if defined?(::User)
  end
end
```
Minimize this — the engine should work without knowing the host app's models.

**Testing engines:**
```ruby
# The engine includes a dummy Rails app for testing
# test/dummy/ contains a minimal Rails app that mounts the engine
# spec/dummy/ for RSpec

# spec/requests/rubyn/dashboard_spec.rb
RSpec.describe "Rubyn::Dashboard", type: :request do
  it "shows the dashboard" do
    get rubyn.root_path
    expect(response).to have_http_status(:ok)
  end
end
```

**Engine migrations:**
```bash
# Copy engine migrations to host app
rails rubyn:install:migrations
rails db:migrate
```
