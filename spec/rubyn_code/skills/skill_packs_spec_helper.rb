# frozen_string_literal: true

# Lightweight spec helper for skill pack specs.
# Loads only the modules under test — avoids pulling in the full
# rubyn_code dependency tree (pastel, tty-*, db, etc.) which
# requires native extensions that may not be available in all
# CI environments.

$LOAD_PATH.unshift File.expand_path('../../../lib', __dir__)

require 'rubyn_code/skills/registry_client'
require 'rubyn_code/skills/pack_installer'
require 'rubyn_code/skills/auto_suggest'
require 'webmock/rspec'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
