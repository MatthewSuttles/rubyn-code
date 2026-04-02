# Ruby: CLI Tools with Thor

## Pattern

Thor is the CLI framework Rails uses internally. It provides command parsing, subcommands, options, and help generation. Use it for any Ruby CLI tool that has more than 2-3 commands.

```ruby
# lib/rubyn/cli.rb
require "thor"

module Rubyn
  class CLI < Thor
    desc "init", "Initialize Rubyn in the current project"
    option :api_key, type: :string, desc: "API key (or set RUBYN_API_KEY env var)"
    def init
      api_key = options[:api_key] || ENV["RUBYN_API_KEY"]
      api_key ||= ask("Enter your Rubyn API key:")

      result = Commands::Init.call(api_key: api_key, project_dir: Dir.pwd)

      if result.success?
        say "✅ Rubyn initialized.", :green
        say "   #{result.project_info}", :cyan
      else
        say "❌ #{result.error}", :red
        exit 1
      end
    end

    desc "refactor FILE", "Refactor a file toward best practices"
    option :model, type: :string, default: "base", enum: %w[light base pro], desc: "AI model tier"
    option :apply, type: :boolean, default: false, desc: "Auto-apply changes without prompting"
    def refactor(file_path)
      ensure_initialized!
      ensure_file_exists!(file_path)

      say "🔍 Analyzing #{file_path}...", :cyan
      context = Context::FileResolver.resolve(file_path, project_dir: Dir.pwd)
      say "   Loading context: #{context.related_files.map { |f| File.basename(f) }.join(', ')}"

      result = Commands::Refactor.call(
        file_path: file_path,
        model_tier: options[:model],
        context: context
      )

      display_streaming_response(result)
      display_credits(result)

      if options[:apply] || yes?("Apply changes? (y/n)")
        apply_changes(result.changes)
        say "✅ Changes applied.", :green
      else
        say "Changes discarded.", :yellow
      end
    end

    desc "spec FILE", "Generate tests for a file"
    option :model, type: :string, default: "base", enum: %w[light base pro]
    option :framework, type: :string, enum: %w[rspec minitest], desc: "Override detected test framework"
    def spec(file_path)
      ensure_initialized!
      ensure_file_exists!(file_path)

      say "🧪 Generating tests for #{file_path}...", :cyan
      result = Commands::Spec.call(file_path: file_path, model_tier: options[:model])

      display_streaming_response(result)
      display_credits(result)

      if yes?("Write spec file? (y/n)")
        write_file(result.spec_path, result.spec_content)
        say "✅ Written to #{result.spec_path}", :green
      end
    end

    desc "review FILE_OR_DIR", "Review code for anti-patterns"
    option :model, type: :string, default: "base", enum: %w[light base pro]
    def review(path)
      ensure_initialized!

      files = File.directory?(path) ? Dir.glob("#{path}/**/*.rb") : [path]
      say "🔍 Reviewing #{files.count} file(s)...", :cyan

      result = Commands::Review.call(files: files, model_tier: options[:model])
      display_streaming_response(result)
      display_credits(result)
    end

    desc "usage", "Show credit balance and recent activity"
    def usage
      ensure_initialized!

      result = Commands::Usage.call
      say result.formatted_output
    end

    desc "version", "Show Rubyn version"
    def version
      say "Rubyn #{Rubyn::VERSION}"
    end

    desc "dashboard", "Open the Rubyn web dashboard"
    def dashboard
      if File.exist?(File.join(Dir.pwd, "config", "routes.rb"))
        say "Dashboard available at http://localhost:3000/rubyn", :cyan
        say "(Make sure your Rails server is running)"
      else
        say "Starting standalone dashboard...", :cyan
        Commands::Dashboard.call(project_dir: Dir.pwd)
      end
    end

    private

    def ensure_initialized!
      unless Rubyn::Config.initialized?
        say "❌ Rubyn not initialized. Run `rubyn init` first.", :red
        exit 1
      end
    end

    def ensure_file_exists!(path)
      unless File.exist?(path)
        say "❌ File not found: #{path}", :red
        exit 1
      end
    end

    def display_streaming_response(result)
      # StreamHandler renders content in real-time via SSE
      result.stream.each do |chunk|
        print chunk.text  # Streams to terminal as it arrives
      end
      puts
    end

    def display_credits(result)
      say "📊 Used #{result.credits_used} credits (#{result.model_tier}) — #{result.balance_remaining} remaining", :cyan
    end

    def apply_changes(changes)
      changes.each do |change|
        write_file(change.path, change.content)
      end
    end

    def write_file(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end
end
```

### The Executable

```ruby
#!/usr/bin/env ruby
# exe/rubyn

require "rubyn"
Rubyn::CLI.start(ARGV)
```

### Gemspec Setup

```ruby
# rubyn.gemspec
spec.executables = ["rubyn"]
spec.bindir = "exe"
```

### Thor Features Used

```ruby
# Options
option :verbose, type: :boolean, default: false, aliases: "-v"
option :output, type: :string, default: "terminal", enum: %w[terminal json file]
option :count, type: :numeric, default: 10

# Ask for input
name = ask("What is your name?")
password = ask("Password:", echo: false)  # Hidden input

# Yes/No confirmation
if yes?("Are you sure?")
  # proceed
end

# Colored output
say "Success!", :green
say "Warning!", :yellow
say "Error!", :red
say "Info", :cyan

# Tables
print_table([
  ["Model", "Credits", "Status"],
  ["Base", "3", "✅"],
  ["Pro", "7", "✅"]
])

# Shell commands
run("bundle exec rspec #{spec_path}")  # Runs and shows output
```

## Why This Is Good

- **Auto-generated help.** `rubyn help`, `rubyn help refactor` — Thor generates help text from `desc` and `option` declarations.
- **Type-checked options.** `type: :boolean`, `type: :numeric`, `enum: %w[light base pro]` — Thor validates before your code runs.
- **Consistent interface.** Every CLI tool built with Thor follows the same patterns. Users familiar with Rails generators, Bundler, or any Thor-based CLI feel at home.
- **Subcommands for free.** Each `desc` + method becomes a subcommand. No routing logic, no argument parsing.
- **Testable.** `Rubyn::CLI.start(["refactor", "app/controllers/orders_controller.rb", "--model", "pro"])` — invoke CLI commands programmatically in tests.

## When To Apply

- **Any CLI tool with 3+ commands.** Thor provides structure, help, and option parsing that OptionParser requires you to build manually.
- **Gem executables.** Thor is the standard for Ruby gem CLIs (Rails, Bundler, Rubocop all use it).

## When NOT To Apply

- **One-off scripts.** A single-purpose script doesn't need Thor. Use `OptionParser` or just `ARGV`.
- **Two commands.** If the CLI is literally `tool do_thing` and `tool --version`, Thor is overkill.
