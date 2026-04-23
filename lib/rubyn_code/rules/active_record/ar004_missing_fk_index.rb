# frozen_string_literal: true

module RubynCode
  module Rules
    module ActiveRecord
      # AR004 — Missing Index on Foreign Key
      #
      # Detects add_column or add_reference calls that introduce a foreign
      # key column without a corresponding add_index in the same migration.
      # Missing indexes on foreign keys cause slow joins and lookups at
      # scale — a common oversight that compounds over time.
      #
      # Positive examples (should flag):
      #
      #   add_column :orders, :user_id, :integer
      #   add_reference :orders, :user, index: false
      #   add_reference :orders, :user, foreign_key: true  # no index: true
      #   add_column :posts, :category_id, :bigint
      #
      # Negative examples (safe):
      #
      #   add_reference :orders, :user, index: true
      #   add_reference :orders, :user  # add_reference defaults to index: true
      #   add_column :orders, :user_id, :integer + add_index :orders, :user_id
      class Ar004MissingFkIndex < Base
        ID = "AR004"
        CATEGORY = :active_record
        SEVERITY = :medium
        RAILS_VERSIONS = [">= 5.0"].freeze
        CONFIDENCE_FLOOR = 0.8

        # Matches add_column calls with a column name ending in _id
        #   add_column :orders, :user_id, :integer
        #   add_column :posts, :category_id, :bigint, null: false
        ADD_COLUMN_FK_PATTERN = /add_column\s+:\w+,\s+:(\w+_id)\b/

        # Matches add_reference with explicit index: false
        #   add_reference :orders, :user, index: false
        ADD_REFERENCE_INDEX_FALSE_PATTERN = /add_reference\s+:\w+,\s+:\w+.*index:\s*false/

        # Matches add_reference that specifies options but omits index
        # (when other options like foreign_key are present but index is missing).
        # Note: bare add_reference defaults to index: true in Rails 5+.
        #   add_reference :orders, :user, foreign_key: true
        #   add_reference :orders, :user, null: false, foreign_key: true
        ADD_REFERENCE_NO_INDEX_PATTERN = /add_reference\s+:\w+,\s+:\w+,(?!.*\bindex:)/

        # Matches add_index calls to identify when a migration adds its own index
        #   add_index :orders, :user_id
        #   add_index :orders, [:user_id, :status]
        ADD_INDEX_PATTERN = /add_index\s+:\w+,\s+(?::(\w+_id)|\[.*?:(\w+_id))/

        class << self
          # Applies to changed migration files only.
          #
          # @param diff_data [Hash] parsed diff information with :files key
          # @return [Boolean]
          def applies_to?(diff_data)
            return false unless diff_data.is_a?(Hash)

            files = diff_data[:files] || diff_data["files"] || []
            files.any? { |f| migration_file?(f) }
          end

          # Returns the prompt module text for LLM evaluation.
          #
          # @return [String]
          def prompt_module
            <<~PROMPT
              ## Rule AR004 — Missing Index on Foreign Key

              **Severity:** medium
              **Category:** active_record

              ### What to look for

              Detect migrations that add a foreign key column without a corresponding
              index. This leads to slow joins and lookups as the table grows.

              1. **`add_column` with a `_id` column** — When `add_column` is used to
                 add a column ending in `_id` (e.g., `user_id`, `category_id`), the
                 migration should also include a matching `add_index` call for that
                 column in the same migration file.

              2. **`add_reference` with `index: false`** — Explicitly disabling the
                 index that `add_reference` adds by default. This is almost always
                 a mistake unless there's a documented reason.

              3. **`add_reference` with options but no `index:`** — When options like
                 `foreign_key: true` or `null: false` are passed but `index:` is
                 omitted, Rails 5+ still defaults to `index: true`. However, if the
                 migration also passes `index: false` explicitly, that's a problem.

              ### What is acceptable

              - `add_reference :table, :ref` with no options (defaults to `index: true`).
              - `add_reference :table, :ref, index: true`.
              - `add_column :table, :ref_id, :integer` paired with `add_index :table, :ref_id`.
              - `add_column` for non-foreign-key columns (not ending in `_id`).
              - Columns like `:external_id` or `:uuid` that are not foreign keys
                (use context to determine this — the column should reference another table).

              ### Output format

              For each finding, report:
              - file path and line number
              - the offending code snippet
              - which sub-pattern was matched (add_column_without_index, add_reference_index_false, add_reference_missing_index)
              - suggested fix
            PROMPT
          end

          # Validates a finding against the diff data to reduce false positives.
          #
          # @param finding  [Hash] the LLM-generated finding
          # @param diff_data [Hash] parsed diff information
          # @return [Boolean]
          def validate(finding, diff_data)
            return false unless finding.is_a?(Hash) && diff_data.is_a?(Hash)

            file = finding[:file] || finding["file"]
            return false if file.nil? || file.empty?

            # Must be a migration file
            return false unless migration_file?(file)

            # Check that the file is in the diff
            files = diff_data[:files] || diff_data["files"] || []
            return false unless files.any? { |f| normalize_path(f) == normalize_path(file) }

            # Check that the snippet contains a relevant pattern
            snippet = finding[:snippet] || finding["snippet"] || ""
            matches_fk_pattern?(snippet)
          end

          # Checks whether a migration file content has an unindexed foreign key.
          # Used by fixture tests to verify pattern matching on full file content.
          #
          # @param content [String] the migration file content
          # @return [Boolean]
          def unindexed_fk?(content)
            return true if content.match?(ADD_REFERENCE_INDEX_FALSE_PATTERN)

            # Collect all _id columns added via add_column
            fk_columns = content.scan(ADD_COLUMN_FK_PATTERN).flatten

            # Collect all indexed columns from add_index calls
            indexed_columns = content.scan(ADD_INDEX_PATTERN).flatten.compact

            # If any add_column FK lacks a matching add_index, flag it
            return true if fk_columns.any? { |col| !indexed_columns.include?(col) }

            # Check add_reference with options that skip index
            # (has options like foreign_key but no index: key at all)
            if content.match?(ADD_REFERENCE_NO_INDEX_PATTERN)
              # Verify it's not a bare add_reference (which defaults to index: true)
              content.each_line.any? do |line|
                line.match?(ADD_REFERENCE_NO_INDEX_PATTERN) &&
                  line.include?(",") &&
                  !line.match?(/\bindex:/)
              end
            else
              false
            end
          end

          private

          # Determines if a file path looks like a Rails migration.
          #
          # @param file [String, Hash] file path string or hash with :path key
          # @return [Boolean]
          def migration_file?(file)
            path = normalize_path(file)
            return false if path.nil?

            path.match?(%r{db/migrate/.*\.rb\z})
          end

          # Checks if a snippet matches any of the FK-without-index patterns.
          #
          # @param snippet [String]
          # @return [Boolean]
          def matches_fk_pattern?(snippet)
            snippet.match?(ADD_COLUMN_FK_PATTERN) ||
              snippet.match?(ADD_REFERENCE_INDEX_FALSE_PATTERN) ||
              snippet.match?(ADD_REFERENCE_NO_INDEX_PATTERN)
          end

          # Extracts a path string from either a String or a Hash.
          #
          # @param file [String, Hash]
          # @return [String, nil]
          def normalize_path(file)
            case file
            when String
              file
            when Hash
              file[:path] || file["path"]
            end
          end
        end
      end
    end
  end
end

RubynCode::Rules::Registry.register(RubynCode::Rules::ActiveRecord::Ar004MissingFkIndex)
