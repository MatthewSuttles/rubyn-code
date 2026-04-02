# Ruby: File I/O

## Pattern

Use block forms for automatic resource cleanup, choose the right I/O method for the data size, and prefer standard library parsers (CSV, JSON, YAML) over manual parsing.

### Reading Files

```ruby
# GOOD: Block form — file is automatically closed when block exits
File.open("data.txt") do |file|
  file.each_line { |line| process(line) }
end

# GOOD: Read entire file at once (small files only — loads into memory)
content = File.read("config.yml")
lines = File.readlines("data.txt", chomp: true)  # Array of lines, newlines stripped

# GOOD: Stream large files line by line (constant memory)
File.foreach("huge_log.txt") do |line|
  next unless line.include?("ERROR")
  log_error(line)
end

# GOOD: Read with encoding
content = File.read("data.csv", encoding: "UTF-8")

# BAD: Manual open without close
file = File.open("data.txt")
content = file.read
# file.close  ← Easy to forget, especially if an exception occurs between open and close
```

### Writing Files

```ruby
# GOOD: Block form for writing
File.open("output.txt", "w") do |file|
  file.puts "Line 1"
  file.puts "Line 2"
end

# GOOD: Write entire string at once
File.write("output.txt", "Hello, world!")
File.write("log.txt", "New entry\n", mode: "a")  # Append mode

# GOOD: Atomic write — prevents partial writes on crash (Rails)
require "fileutils"
# Write to temp file, then rename (atomic on most filesystems)
temp_path = "#{path}.tmp"
File.write(temp_path, content)
FileUtils.mv(temp_path, path)

# Rails provides this built-in:
File.atomic_write("config/settings.yml") do |file|
  file.write(settings.to_yaml)
end
```

### Temporary Files

```ruby
require "tempfile"

# GOOD: Tempfile with block — auto-deleted when block exits
Tempfile.create("report") do |temp|
  temp.write(generate_csv_data)
  temp.rewind
  upload_to_s3(temp)
end
# File is deleted here

# GOOD: Tempfile with specific extension
Tempfile.create(["export", ".csv"]) do |temp|
  temp.path  # => "/tmp/export20260320-12345.csv"
  CSV.open(temp.path, "w") do |csv|
    csv << ["name", "email"]
    users.each { |u| csv << [u.name, u.email] }
  end
  send_email_with_attachment(temp.path)
end
```

### CSV

```ruby
require "csv"

# Reading
CSV.foreach("orders.csv", headers: true) do |row|
  Order.create!(
    reference: row["reference"],
    total: row["total"].to_i,
    status: row["status"]
  )
end

# Reading into array of hashes
data = CSV.read("data.csv", headers: true).map(&:to_h)

# Writing
CSV.open("export.csv", "w") do |csv|
  csv << %w[reference total status created_at]
  orders.each do |order|
    csv << [order.reference, order.total, order.status, order.created_at.iso8601]
  end
end

# Generate CSV string (for send_data in controllers)
csv_string = CSV.generate do |csv|
  csv << %w[name email plan]
  users.each { |u| csv << [u.name, u.email, u.plan] }
end
send_data csv_string, filename: "users-#{Date.current}.csv"
```

### JSON

```ruby
require "json"

# Parsing
data = JSON.parse(File.read("config.json"))
data = JSON.parse(response.body, symbolize_names: true)  # Symbol keys

# Generating
json_string = { name: "Alice", orders: 5 }.to_json
pretty_json = JSON.pretty_generate({ name: "Alice", orders: 5 })

# Safe parsing (handle invalid JSON)
begin
  data = JSON.parse(input)
rescue JSON::ParserError => e
  Rails.logger.error("Invalid JSON: #{e.message}")
  data = {}
end
```

### YAML

```ruby
require "yaml"

# SAFE: Permitted classes only (Ruby 3.1+ default)
config = YAML.safe_load_file("config.yml", permitted_classes: [Date, Time, Symbol])

# For Rails config files
config = YAML.safe_load(
  ERB.new(File.read("config/database.yml")).result,
  permitted_classes: [Symbol],
  aliases: true
)

# Writing
File.write("output.yml", data.to_yaml)

# DANGEROUS: Never use YAML.load on untrusted input — it can execute arbitrary code
# YAML.load(user_input)  ← SECURITY VULNERABILITY
# YAML.safe_load(user_input)  ← SAFE
```

### Path Handling

```ruby
# GOOD: Use Pathname or File.join — never string concatenation for paths
require "pathname"

path = Pathname.new("app/models")
path / "order.rb"                    # => #<Pathname:app/models/order.rb>
path.join("concerns", "sluggable.rb") # => #<Pathname:app/models/concerns/sluggable.rb>

File.join("app", "models", "order.rb")  # => "app/models/order.rb" (cross-platform)

# Useful Pathname methods
path = Pathname.new("app/models/order.rb")
path.exist?        # => true
path.extname       # => ".rb"
path.basename      # => #<Pathname:order.rb>
path.dirname       # => #<Pathname:app/models>
path.expand_path   # => #<Pathname:/home/user/project/app/models/order.rb>

# BAD: String concatenation — breaks on different OS path separators
"app" + "/" + "models" + "/" + "order.rb"
```

### Directory Operations

```ruby
# List files
Dir.glob("app/models/**/*.rb")         # All .rb files recursively
Dir.glob("spec/**/*_spec.rb")          # All spec files
Dir["app/services/*.rb"]               # Shorthand for glob

# Create directories
FileUtils.mkdir_p("app/services/orders")  # Creates intermediate dirs

# Check existence
File.exist?("app/models/order.rb")
File.directory?("app/services")
File.file?("Gemfile")
```

## Why This Is Good

- **Block forms guarantee cleanup.** Files are closed even if exceptions occur. No resource leaks.
- **`File.foreach` streams.** Processing a 10GB log file uses constant memory, not 10GB.
- **Standard library parsers handle edge cases.** CSV with quoted commas, JSON with unicode escapes, YAML with anchors — don't parse these manually.
- **`YAML.safe_load` prevents RCE.** `YAML.load` can execute arbitrary Ruby code from crafted YAML. Always use `safe_load`.
- **`Pathname` is cross-platform.** No hardcoded `/` separators that break on Windows.

## When To Apply

- **Always use block forms** for `File.open`, `Tempfile.create`, `CSV.open`.
- **`File.foreach` for large files** (logs, data imports, CSVs over 1MB).
- **`File.read` for small files** (config, templates, under 1MB).
- **`YAML.safe_load` always** — never `YAML.load` on any input.
- **`JSON.parse` with rescue** — external JSON may be malformed.
