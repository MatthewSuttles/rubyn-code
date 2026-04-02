# Design Pattern: Template Method

## Pattern

Define the skeleton of an algorithm in a base class, letting subclasses override specific steps without changing the algorithm's structure. The base class controls the *what* and *when*; subclasses control the *how*.

```ruby
# Base class defines the algorithm skeleton
class Reports::BaseReport
  def generate(start_date, end_date)
    data = fetch_data(start_date, end_date)
    filtered = apply_filters(data)
    formatted = format_output(filtered)
    add_metadata(formatted, start_date, end_date)
  end

  private

  # Steps that subclasses MUST override
  def fetch_data(start_date, end_date)
    raise NotImplementedError, "#{self.class} must implement #fetch_data"
  end

  def format_output(data)
    raise NotImplementedError, "#{self.class} must implement #format_output"
  end

  # Hook methods — subclasses CAN override, but don't have to
  def apply_filters(data)
    data  # Default: no filtering
  end

  def add_metadata(output, start_date, end_date)
    {
      report_type: self.class.name.demodulize.underscore,
      generated_at: Time.current.iso8601,
      period: "#{start_date} to #{end_date}",
      data: output
    }
  end
end

# Subclass: Revenue report
class Reports::RevenueReport < Reports::BaseReport
  private

  def fetch_data(start_date, end_date)
    Order.where(created_at: start_date..end_date)
         .group(:status)
         .sum(:total)
  end

  def format_output(data)
    data.map { |status, total| { status: status, total: total.round(2) } }
  end
end

# Subclass: User activity report with custom filtering
class Reports::UserActivityReport < Reports::BaseReport
  private

  def fetch_data(start_date, end_date)
    User.where(last_active_at: start_date..end_date)
        .select(:id, :email, :last_active_at, :plan)
  end

  def apply_filters(data)
    data.where.not(plan: "free")  # Override hook: exclude free users
  end

  def format_output(data)
    data.map { |u| { email: u.email, plan: u.plan, last_active: u.last_active_at.iso8601 } }
  end
end

# Subclass: Credit usage report
class Reports::CreditUsageReport < Reports::BaseReport
  private

  def fetch_data(start_date, end_date)
    CreditLedger.where(created_at: start_date..end_date)
                .joins(:user)
                .group("users.email")
                .sum(:amount)
  end

  def format_output(data)
    data.sort_by { |_, amount| amount }
        .map { |email, amount| { email: email, credits_used: amount.abs } }
  end
end

# Usage — all reports follow the same algorithm, different data/formatting
revenue = Reports::RevenueReport.new.generate(30.days.ago, Date.today)
activity = Reports::UserActivityReport.new.generate(7.days.ago, Date.today)
credits = Reports::CreditUsageReport.new.generate(1.month.ago.beginning_of_month, 1.month.ago.end_of_month)
```

## Why This Is Good

- **Algorithm is defined once.** The sequence — fetch, filter, format, add metadata — lives in `BaseReport`. No subclass can accidentally skip the metadata step or reorder the operations.
- **Variation without duplication.** Each report only implements what's different (data source, formatting). The shared steps (metadata, the overall flow) are inherited.
- **Hook methods provide optional customization.** `apply_filters` has a default (no-op). Subclasses override it only when they need filtering. No empty method stubs needed.
- **New reports are easy.** Create a new subclass, implement `fetch_data` and `format_output`, done. The algorithm skeleton works automatically.

## Anti-Pattern

Copy-pasting the algorithm into each report class:

```ruby
class RevenueReport
  def generate(start_date, end_date)
    data = Order.where(created_at: start_date..end_date).group(:status).sum(:total)
    formatted = data.map { |status, total| { status: status, total: total } }
    { report_type: "revenue", generated_at: Time.current.iso8601, period: "#{start_date} to #{end_date}", data: formatted }
  end
end

class UserActivityReport
  def generate(start_date, end_date)
    data = User.where(last_active_at: start_date..end_date)
    formatted = data.map { |u| { email: u.email, last_active: u.last_active_at } }
    { report_type: "user_activity", generated_at: Time.current.iso8601, period: "#{start_date} to #{end_date}", data: formatted }
  end
end
```

The metadata hash is duplicated in every report. Changing the metadata format means editing every class.

## When To Apply

- **Multiple classes follow the same algorithm with different details.** Reports, importers, exporters, notification handlers, data processors.
- **You want to enforce a sequence of steps.** The base class guarantees that filtering always happens after fetching and before formatting.
- **Common behavior + specific behavior.** Metadata generation is common. Data fetching is specific.

## When NOT To Apply

- **Two classes with minor differences.** If only `fetch_data` varies and everything else is identical, a single class with an injected strategy (proc or data source object) is simpler than inheritance.
- **Ruby modules might be better.** If you need to mix the template into unrelated class hierarchies, use a module with a template method instead of inheritance.
- **Don't force inheritance for code reuse.** If the subclasses don't have a genuine "is-a" relationship, prefer composition (Strategy pattern) over inheritance (Template Method).

## Edge Cases

**Template Method via modules (no inheritance needed):**

```ruby
module Importable
  def import(file_path)
    rows = parse(file_path)
    validated = rows.select { |row| valid?(row) }
    validated.each { |row| persist(row) }
    { imported: validated.size, rejected: rows.size - validated.size }
  end

  private

  def parse(file_path) = raise(NotImplementedError)
  def valid?(row) = true  # Hook: override to add validation
  def persist(row) = raise(NotImplementedError)
end

class CsvOrderImporter
  include Importable

  private

  def parse(file_path) = CSV.read(file_path, headers: true).map(&:to_h)
  def valid?(row) = row["total"].to_f > 0
  def persist(row) = Order.create!(row)
end
```

This avoids class inheritance while still providing the template method's algorithmic skeleton.
