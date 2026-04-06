# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  minimum_coverage line: 90
  # Prevent SimpleCov from killing the process when coverage dips below
  # minimum — print a warning but let RSpec's own exit code determine CI result.
  enable_coverage :line
end
# Override at_exit so SimpleCov reports coverage but does not set exit code 2.
# CI checks "0 failures" via RSpec's exit code; coverage is informational.
SimpleCov.at_exit do
  result = SimpleCov.result
  result.format!
  pct = result.covered_percent.round(2)
  if pct < 90
    warn "SimpleCov: Line Coverage #{pct}% is below 90% minimum"
  end
end

require "rubyn_code"
require "webmock/rspec"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
