# frozen_string_literal: true

module RubynCode
  module DB
    # Reads migration files from db/migrations/, tracks applied versions
    # in a schema_migrations table, and applies new migrations in order.
    #
    # Supports two migration formats:
    # - `.sql` files: executed statement-by-statement inside a transaction
    # - `.rb` files: loaded and called via `ModuleName.up(connection)`
    class Migrator
      # @return [String] absolute path to the migrations directory
      MIGRATIONS_DIR = File.expand_path('../../../db/migrations', __dir__).freeze

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
        available_migrations.reject { |version, _| applied.include?(version) } # rubocop:disable Style/HashExcept
      end

      # Returns the set of already-applied migration versions.
      #
      # @return [Set<Integer>]
      def applied_versions
        rows = @connection.query(
          'SELECT version FROM schema_migrations ORDER BY version'
        ).to_a
        rows.to_set { |row| row['version'] }
      end

      # Returns the current schema version (highest applied migration).
      #
      # @return [Integer, nil]
      def current_version
        row = @connection.query(
          'SELECT MAX(version) AS max_version FROM schema_migrations'
        ).to_a.first
        row && row['max_version']
      end

      # Lists all available migration files sorted by version.
      #
      # @return [Array<Array(Integer, String)>] pairs of [version, file_path]
      def available_migrations
        all = Dir.glob(File.join(MIGRATIONS_DIR, '*'))
                 .select { |path| path.end_with?('.sql', '.rb') }
                 .filter_map { |path| parse_migration_file(path) }

        deduplicate_migrations(all)
      end

      def deduplicate_migrations(all)
        by_version = {}
        all.each do |version, path|
          by_version[version] = [version, path] if !by_version[version] || path.end_with?('.rb')
        end
        by_version.values.sort_by(&:first)
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
        @connection.transaction do
          if path.end_with?('.rb')
            apply_ruby_migration(path)
          else
            apply_sql_migration(path)
          end

          @connection.execute(
            'INSERT INTO schema_migrations (version) VALUES (?)', [version]
          )
        end
      end

      def apply_sql_migration(path)
        sql = File.read(path)
        split_statements(sql).each do |statement|
          @connection.execute(statement)
        end
      end

      # Loads a Ruby migration file and calls its `.up` method.
      # The migration module must define `module_function def up(db)`.
      def apply_ruby_migration(path)
        require path
        module_name = extract_module_name(path)
        mod = Object.const_get(module_name)
        mod.up(@connection)
      end

      # Derives the module name from a migration filename.
      # e.g. "011_fix_mailbox_messages_columns.rb" -> "Migration011FixMailboxMessagesColumns"
      def extract_module_name(path)
        basename = File.basename(path, '.rb')
        "Migration#{basename.split('_').map(&:capitalize).join}"
      end

      # Splits a SQL file into individual statements, handling semicolons
      # inside string literals and ignoring empty/comment-only fragments.
      #
      # @param sql [String]
      # @return [Array<String>]
      def split_statements(sql)
        statements = []
        current = +''
        in_block = false

        sql.each_line do |line|
          in_block, current = process_sql_line(line, statements, current, in_block)
        end

        finalize_statements(statements, current)
      end

      def process_sql_line(line, statements, current, in_block)
        stripped = line.strip
        in_block = true if begin_block?(stripped)
        current << line

        if in_block && stripped.match?(/\bEND\b\s*;?\s*$/i)
          statements << current.strip.chomp(';')
          [false, +'']
        elsif !in_block && stripped.end_with?(';')
          append_statement(statements, current)
          [false, +'']
        else
          [in_block, current]
        end
      end

      def begin_block?(stripped)
        stripped.match?(/\bBEGIN\b/i) &&
          !stripped.match?(/\ABEGIN\s+(IMMEDIATE|DEFERRED|EXCLUSIVE)/i)
      end

      def append_statement(statements, current)
        stmt = current.strip.chomp(';').strip
        return if stmt.empty? || (stmt.match?(/\A\s*--/) && !stmt.include?("\n"))

        statements << stmt
      end

      def finalize_statements(statements, current)
        remainder = current.strip.chomp(';').strip
        statements << remainder unless remainder.empty?

        statements.reject { |s| comment_only?(s) }
      end

      def comment_only?(stmt)
        stmt.lines.all? { |l| l.strip.empty? || l.strip.start_with?('--') }
      end

      # Extracts the version number and name from a migration filename.
      #
      # @param path [String]
      # @return [Array(Integer, String), nil]
      def parse_migration_file(path)
        ext = File.extname(path)
        basename = File.basename(path, ext)
        match = basename.match(/\A(\d+)_/)
        return nil unless match

        version = match[1].to_i
        [version, path]
      end
    end
  end
end
