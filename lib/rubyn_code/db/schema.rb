# frozen_string_literal: true

module RubynCode
  module DB
    # Provides schema introspection helpers and version checking
    # for the database.
    class Schema
      # @param connection [Connection] the database connection
      def initialize(connection)
        @connection = connection
      end

      # Returns the current schema version (highest applied migration).
      #
      # @return [Integer, nil] the version number, or nil if no migrations applied
      def current_version
        row = @connection.query(
          'SELECT MAX(version) AS max_version FROM schema_migrations'
        ).to_a.first
        row && row['max_version']
      rescue StandardError
        nil
      end

      # Returns all applied migration versions in order.
      #
      # @return [Array<Integer>]
      def applied_versions
        @connection.query(
          'SELECT version FROM schema_migrations ORDER BY version'
        ).to_a.map { |row| row['version'] }
      rescue StandardError
        []
      end

      # Checks whether a specific migration version has been applied.
      #
      # @param version [Integer]
      # @return [Boolean]
      def version_applied?(version)
        rows = @connection.query(
          'SELECT 1 FROM schema_migrations WHERE version = ?', [version]
        ).to_a
        !rows.empty?
      rescue StandardError
        false
      end

      # Returns a list of table names in the database (excluding internal SQLite tables).
      #
      # @return [Array<String>]
      def tables
        @connection.query(
          "SELECT name FROM sqlite_master WHERE type = 'table' " \
          "AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).to_a.map { |row| row['name'] }
      end

      # Returns column information for the given table.
      #
      # @param table_name [String]
      # @return [Array<Hash>] each hash has keys: cid, name, type, notnull, dflt_value, pk
      def columns(table_name)
        @connection.query("PRAGMA table_info(#{quote_identifier(table_name)})").to_a
      end

      # Returns index information for the given table.
      #
      # @param table_name [String]
      # @return [Array<Hash>]
      def indexes(table_name)
        @connection.query("PRAGMA index_list(#{quote_identifier(table_name)})").to_a
      end

      # Checks whether a given table exists in the database.
      #
      # @param table_name [String]
      # @return [Boolean]
      def table_exists?(table_name)
        rows = @connection.query(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [table_name]
        ).to_a
        !rows.empty?
      end

      # Returns true if the schema is up to date with all available migrations.
      #
      # @param migrator [Migrator]
      # @return [Boolean]
      def up_to_date?(migrator)
        migrator.pending_migrations.empty?
      end

      private

      # Safely quotes a SQL identifier to prevent injection.
      #
      # @param name [String]
      # @return [String]
      def quote_identifier(name)
        "\"#{name.gsub('"', '""')}\""
      end
    end
  end
end
