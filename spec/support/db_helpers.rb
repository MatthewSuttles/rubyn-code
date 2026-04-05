# frozen_string_literal: true

require 'sqlite3'

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

    def transaction(&)
      @db.transaction(&)
    end
  end

  def setup_test_db
    db = SQLite3::Database.new(':memory:')
    db.results_as_hash = true
    db.execute('PRAGMA foreign_keys = ON')
    TestDBWrapper.new(db)
  end

  # Sets up a test DB with real schema tables for integration-level specs.
  # Runs all .sql migrations from db/migrations/ in order.
  def setup_test_db_with_tables
    wrapper = setup_test_db
    migrations_dir = File.expand_path('../../db/migrations', __dir__)

    Dir.glob(File.join(migrations_dir, '*.sql')).each do |path|
      sql = File.read(path)
      sql.split(';').each do |stmt|
        stmt = stmt.strip
        next if stmt.empty?

        wrapper.execute(stmt)
      rescue SQLite3::SQLException
        # Some statements (FTS virtual tables, triggers) may not work in
        # all SQLite builds — skip them in tests.
        nil
      end
    end

    wrapper
  end
end

RSpec.configure do |config|
  config.include DBHelpers
end
