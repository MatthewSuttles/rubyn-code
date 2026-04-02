# frozen_string_literal: true

require "sqlite3"
require "monitor"
require "fileutils"

module RubynCode
  module DB
    # Manages a singleton SQLite3 database connection with WAL mode,
    # foreign keys, and thread-safe access.
    class Connection
      include MonitorMixin

      class << self
        # Returns the singleton Connection instance, optionally initializing
        # it with the given database path on first call.
        #
        # @param path [String] path to the SQLite3 database file
        # @return [Connection]
        def instance(path = nil)
          @mutex ||= Mutex.new
          @mutex.synchronize do
            if @instance.nil?
              path ||= Config::Defaults::DB_FILE
              FileUtils.mkdir_p(File.dirname(path))
              @instance = new(path)
            end
            @instance
          end
        end

        # Executes a write statement (INSERT, UPDATE, DELETE, DDL).
        #
        # @param sql [String] the SQL statement
        # @param params [Array] bind parameters
        # @return [void]
        def execute(sql, params = [])
          instance.execute(sql, params)
        end

        # Executes a read query and returns rows as hashes.
        #
        # @param sql [String] the SQL query
        # @param params [Array] bind parameters
        # @return [Array<Hash>]
        def query(sql, params = [])
          instance.query(sql, params)
        end

        # Wraps a block in a database transaction with automatic
        # commit/rollback semantics. Supports nested calls via SAVEPOINTs.
        #
        # @yield the block to execute within the transaction
        # @return [Object] the return value of the block
        def transaction(&block)
          instance.transaction(&block)
        end

        # Tears down the singleton instance. Intended for test cleanup.
        #
        # @return [void]
        def reset!
          @mutex ||= Mutex.new
          @mutex.synchronize do
            if @instance
              @instance.close
              @instance = nil
            end
          end
        end
      end

      # @param path [String] path to the SQLite3 database file
      def initialize(path)
        super() # MonitorMixin
        @path = path
        @db = SQLite3::Database.new(path)
        @transaction_depth = 0
        configure_connection
      end

      # Executes a write statement with bind parameters.
      #
      # @param sql [String]
      # @param params [Array]
      # @return [void]
      def execute(sql, params = [])
        synchronize do
          @db.execute(sql, params)
        end
      end

      # Executes a read query and returns all matching rows.
      #
      # @param sql [String]
      # @param params [Array]
      # @return [Array<Hash>]
      def query(sql, params = [])
        synchronize do
          @db.execute(sql, params)
        end
      end

      # Wraps a block in a transaction. Nested calls use SAVEPOINTs
      # to avoid SQLite "cannot start a transaction within a transaction" errors.
      #
      # @yield the block to execute
      # @return [Object] the block's return value
      def transaction
        synchronize do
          if @transaction_depth.zero?
            begin_top_level_transaction
          else
            begin_savepoint
          end

          @transaction_depth += 1
          begin
            result = yield
            if @transaction_depth == 1
              @db.execute("COMMIT")
            else
              @db.execute("RELEASE SAVEPOINT sp_#{@transaction_depth}")
            end
            result
          rescue StandardError => e
            if @transaction_depth == 1
              @db.execute("ROLLBACK")
            else
              @db.execute("ROLLBACK TO SAVEPOINT sp_#{@transaction_depth}")
              @db.execute("RELEASE SAVEPOINT sp_#{@transaction_depth}")
            end
            raise e
          ensure
            @transaction_depth -= 1
          end
        end
      end

      # Closes the underlying database connection.
      #
      # @return [void]
      def close
        synchronize do
          @db.close unless @db.closed?
        end
      end

      # Returns whether the connection is open.
      #
      # @return [Boolean]
      def open?
        !@db.closed?
      end

      private

      def configure_connection
        @db.results_as_hash = true
        @db.execute("PRAGMA journal_mode = WAL")
        @db.execute("PRAGMA foreign_keys = ON")
        @db.execute("PRAGMA busy_timeout = 5000")
        @db.execute("PRAGMA synchronous = NORMAL")
        @db.execute("PRAGMA cache_size = -20000") # 20 MB
      end

      def begin_top_level_transaction
        @db.execute("BEGIN IMMEDIATE")
      end

      def begin_savepoint
        @db.execute("SAVEPOINT sp_#{@transaction_depth + 1}")
      end
    end
  end
end
