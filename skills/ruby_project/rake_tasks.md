# Ruby: Rake Tasks

## Pattern

Rake is Ruby's task runner. Organize tasks in namespaces, document them with descriptions, and keep task bodies thin by delegating to service objects or scripts.

```ruby
# Rakefile
require_relative "config/environment"

# Import tasks from lib/tasks/
Dir[File.join(__dir__, "lib", "tasks", "**", "*.rake")].each { |f| load f }
```

```ruby
# lib/tasks/db.rake
namespace :db do
  desc "Sync best practice documents to database and generate embeddings"
  task sync_best_practices: :environment do
    puts "Syncing best practices..."
    result = BestPractices::SyncService.call
    puts "Synced #{result.created} new, updated #{result.updated}, removed #{result.removed}"
  end

  desc "Backfill embeddings for documents missing them"
  task backfill_embeddings: :environment do
    documents = BestPracticeDocument.where(embedding: nil)
    puts "Backfilling #{documents.count} documents..."

    documents.find_each do |doc|
      Embeddings::DocumentEmbedder.call(doc)
      print "."
    end

    puts "\nDone!"
  end

  desc "Reset all embeddings (re-embed everything)"
  task reset_embeddings: :environment do
    abort("This will delete all embeddings. Run with CONFIRM=true") unless ENV["CONFIRM"] == "true"

    CodeEmbedding.delete_all
    BestPracticeDocument.update_all(embedding: nil, last_embedded_at: nil)
    puts "All embeddings cleared. Run db:backfill_embeddings to regenerate."
  end
end
```

```ruby
# lib/tasks/credits.rake
namespace :credits do
  desc "Report credit usage for the current month"
  task monthly_report: :environment do
    report = Credits::MonthlyReportService.call(Date.current)

    puts "=== Credit Report: #{Date.current.strftime('%B %Y')} ==="
    puts "Total users: #{report.active_users}"
    puts "Total credits used: #{report.total_credits}"
    puts "Total revenue: $#{format('%.2f', report.revenue / 100.0)}"
    puts "Average credits/user: #{report.avg_per_user}"
  end

  desc "Grant credits to a user (usage: rake credits:grant USER_ID=1 AMOUNT=100)"
  task grant: :environment do
    user_id = ENV.fetch("USER_ID") { abort "USER_ID required" }
    amount = ENV.fetch("AMOUNT") { abort "AMOUNT required" }.to_i
    abort "AMOUNT must be positive" unless amount > 0

    user = User.find(user_id)
    user.credit_ledger_entries.create!(amount: amount, description: "Manual grant via rake")
    puts "Granted #{amount} credits to #{user.email}. New balance: #{user.credit_balance}"
  end
end
```

```ruby
# lib/tasks/data.rake
namespace :data do
  desc "Import orders from CSV (usage: rake data:import_orders FILE=orders.csv)"
  task import_orders: :environment do
    file = ENV.fetch("FILE") { abort "FILE required" }
    abort "File not found: #{file}" unless File.exist?(file)

    imported = 0
    errors = 0

    CSV.foreach(file, headers: true) do |row|
      result = Orders::ImportService.call(row.to_h)
      if result.success?
        imported += 1
      else
        errors += 1
        puts "Row #{$.}: #{result.error}"
      end
    end

    puts "Imported: #{imported}, Errors: #{errors}"
  end
end
```

### Default Task and Test Task

```ruby
# Rakefile
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test
```

## Why This Is Good

- **`desc` makes tasks discoverable.** `rake -T` lists all tasks with descriptions. Undocumented tasks are invisible.
- **Namespaces organize tasks.** `rake db:sync_best_practices`, `rake credits:grant`, `rake data:import_orders` — clear, grouped, no collisions.
- **ENV parameters for input.** `USER_ID=1 AMOUNT=100 rake credits:grant` is explicit and scriptable. No interactive prompts.
- **Task bodies are thin.** The task calls a service object. The service contains the logic, is testable, and reusable outside of rake.
- **Safety guards for destructive tasks.** `abort unless ENV["CONFIRM"]` prevents accidental data deletion.

## Anti-Pattern

```ruby
# BAD: Business logic inside the rake task
task :process_orders do
  Order.where(status: :pending).each do |order|
    order.line_items.each do |item|
      product = Product.find(item.product_id)
      product.update!(stock: product.stock - item.quantity)
    end
    order.update!(status: :confirmed)
    OrderMailer.confirmation(order).deliver_now
  end
end
# 10 lines of untestable, unreusable business logic
```

## When To Apply

- **Every operational task.** Data migrations, reporting, manual operations, maintenance scripts.
- **One-off tasks stay in Rake.** Don't build an admin UI for a task you'll run once.
- **Keep the body under 10 lines.** If it's longer, extract to a service object.
