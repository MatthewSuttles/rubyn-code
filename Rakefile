# frozen_string_literal: true

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

desc 'Run the Rubyn self-test smoke test'
task :self_test do
  require_relative 'lib/rubyn_code'
  test = RubynCode::SelfTest.new(project_root: __dir__)
  exit(1) unless test.run!
end

task default: :spec
