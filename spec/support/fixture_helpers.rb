# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "json"

module FixtureHelpers
  def fixture_path(name)
    File.join(__dir__, "..", "fixtures", name)
  end

  def load_fixture(name)
    File.read(fixture_path(name))
  end

  def load_json_fixture(name)
    JSON.parse(load_fixture(name))
  end

  def with_temp_project(&block)
    Dir.mktmpdir("rubyn_test_") do |dir|
      block.call(dir)
    end
  end
end

RSpec.configure do |config|
  config.include FixtureHelpers
end
