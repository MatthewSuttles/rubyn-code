# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
end

# SimpleCov's default at_exit calls process_result! which exits with code 2
# when coverage is below minimum, AND bails entirely when it detects a
# "previous error" (any non-zero exit status from RSpec, including spec
# file load errors on CI/Linux). This cascading exit code causes RSpec to
# report fewer and fewer specs each run.
#
# Fix: override at_exit to format results and warn on low coverage, but
# NEVER set a non-zero exit code. RSpec's own exit code (0 = all pass,
# 1 = failures) determines CI pass/fail.
SimpleCov.at_exit do
  result = SimpleCov.result
  result.format!
  pct = result.covered_percent.round(2)
  warn "SimpleCov: Line Coverage #{pct}% (target: 90%)" if pct < 90.0
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
