# frozen_string_literal: true

require_relative "lib/rubyn_code/version"

Gem::Specification.new do |spec|
  spec.name          = "rubyn-code"
  spec.version       = RubynCode::VERSION
  spec.authors       = ["fadedmaturity"]
  spec.summary       = "Ruby & Rails agentic coding assistant"
  spec.description   = "An AI-powered CLI coding assistant specialized for Ruby and Rails, " \
                       "featuring a 16-layer agentic architecture, local SQLite persistence, and Claude OAuth."
  spec.homepage      = "https://rubyn.dev"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.files         = Dir["lib/**/*", "exe/*", "skills/**/*", "db/**/*", "LICENSE", "README.md"]
  spec.bindir        = "exe"
  spec.executables   = ["rubyn-code"]
  spec.require_paths = ["lib"]

  # Core
  spec.add_dependency "sqlite3", "~> 2.0"
  spec.add_dependency "faraday", ">= 2.0", "< 3.0"

  # CLI & Terminal
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "rouge", ">= 4.0", "< 5.0"
  spec.add_dependency "tty-prompt", "~> 0.23"
  spec.add_dependency "tty-spinner", "~> 0.9"
  spec.add_dependency "tty-markdown", "~> 0.7"

  # CLI input (removed from Ruby 4.0 stdlib)
  spec.add_dependency "reline", ">= 0.5"

  # Auth
  spec.add_dependency "webrick", "~> 1.8"

  spec.post_install_message = <<~MSG
    Rubyn Code installed! Run `rubyn-code --setup` to pin it to this Ruby
    so it works in any project regardless of .ruby-version.

    Tip: Install with your latest Ruby for best performance:
      RBENV_VERSION=4.0.2 gem install rubyn-code && rubyn-code --setup
  MSG
end
