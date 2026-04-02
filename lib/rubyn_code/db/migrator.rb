# frozen_string_literal: true

module RubynCode
  module DB
    # Reads SQL migration files from db/migrations/, tracks applied versions
    # in a schema_migrations table, and applies new migrations in order.
    class Migrator
      # @return [String] absolute path to the migrations directory
      MIGRATIONS_DIR = File.expand_path("../../../db/migrations", __dir__).freeze

      # @param connection [Connection] the database connection to migrate
      def initialize(connection)
        @connection = connection
        ensure_schema_migrations_table
      end

      # Applies all pending migrations in version order.
      #
      # @return [Array<Integer>] list of newly applied migration versions
      def migrate!
        pending = pending_migrations
        return [] if pending.empty?

        applied = []
        pending.each do |version, path|
          apply_migration(version, path)
          applied << version
        end
        applied
      end

      # Returns migration versions that have not yet been applied.
      #
      # @return [Array<Array(Integer, String)>] pairs of [version, file_path]
      def pending_migrations
        applied = applied_versions
        available_migrations.reject { |version, _| applied.include?(version) }
      end

      # Returns the set of already-applied migration versions.
      #
      # @return [Set<Integer>]
      def applied_versions
        rows = @connection.query(
          "SELECT version FROM schema_migrations ORDER BY version"
        ).to_a
        rows.map { |row| row["version"] }.to_set
      end

      # Returns the current schema version (highest applied migration).
      #
      # @return [Integer, nil]
      def current_version
        row = @connection.query(
          "SELECT MAX(version) AS max_version FROM schema_migrations"
        ).to_a.first
        row && row["max_version"]
      end

      # Lists all available migration files sorted by version.
      #
      # @return [Array<Array(Integer, String)>] pairs of [version, file_path]
      def available_migrations
        pattern = File.join(MIGRATIONS_DIR, "*.sql")
        Dir.glob(pattern)
           .map { |path| parse_migration_file(path) }
           .compact
           .sort_by(&:first)
      end

      private

      def ensure_schema_migrations_table
        @connection.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY,
            applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
          )
        SQL
      end

      def apply_migration(version, path)
        sql = File.read(path)
        @connection.transaction do
          # Execute each statement separately (SQLite doesn't support multi-statement execute)
          split_statements(sql).each do |statement|
            @connection.execute(statement)
          end
          @connection.execute(
            "INSERT INTO schema_migrations (version) VALUES (?)", [version]
          )
        end
      end

      # Splits a SQL file into individual statements, handling semicolons
      # inside string literals and ignoring empty/comment-only fragments.
      #
      # @param sql [String]
      # @return [Array<String>]
      def split_statements(sql)
        statements = []
        current = +""
        in_block = false

        sql.each_line do |line|
          stripped = line.strip

          # Track BEGIN/END blocks (e.g., triggers)
          in_block = true if stripped.match?(/\bBEGIN\b/i) && !stripped.match?(/\ABEGIN\s+(IMMEDIATE|DEFERRED|EXCLUSIVE)/i)
          current << line

          if in_block
            if stripped.match?(/\bEND\b\s*;?\s*$/i)
              in_block = false
              statements << current.strip.chomp(";")
              current = +""
            end
          elsif stripped.end_with?(";")
            stmt = current.strip.chomp(";").strip
            statements << stmt unless stmt.empty? || (stmt.match?(/\A\s*--/) && !stmt.include?("\n"))
            current = +""
          end
        end

        # Handle any remaining content
        remainder = current.strip.chomp(";").strip
        statements << remainder unless remainder.empty?

        statements
      end

      # Extracts the version number and name from a migration filename.
      #
      # @param path [String]
      # @return [Array(Integer, String), nil]
      def parse_migration_file(path)
        basename = File.basename(path, ".sql")
        match = basename.match(/\A(\d+)_/)
        return nil unless match

        version = match[1].to_i
        [version, path]
      end
    end
  end
end
