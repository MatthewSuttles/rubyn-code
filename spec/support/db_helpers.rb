# frozen_string_literal: true

require "sqlite3"

module DBHelpers
  # Lightweight wrapper around a raw SQLite3::Database that mirrors the
  # interface of RubynCode::DB::Connection expected by the library code.
  # In particular, `query` must return an Array (not a lazy HashResultSet)
  # so that callers can use `.empty?`, `.first`, `.map`, etc.
  class TestDBWrapper
    def initialize(raw_db)
      @db = raw_db
    end

    def execute(sql, params = [])
      @db.execute(sql, params)
    end

    def query(sql, params = [])
      @db.execute(sql, params)
    end

    def transaction(&block)
      @db.transaction(&block)
    end
  end

  def setup_test_db
    db = SQLite3::Database.new(":memory:")
    db.results_as_hash = true
    db.execute("PRAGMA foreign_keys = ON")
    TestDBWrapper.new(db)
  end
end

RSpec.configure do |config|
  config.include DBHelpers
end
