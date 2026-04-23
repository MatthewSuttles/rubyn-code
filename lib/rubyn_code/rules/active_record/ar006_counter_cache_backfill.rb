# frozen_string_literal: true

module RubynCode
  module Rules
    module ActiveRecord
      # AR006 — counter_cache Without Backfill
      #
      # Detects `counter_cache: true` added to a `belongs_to` association
      # without a corresponding data migration to backfill existing counter
      # values. Without a backfill, existing records will show a count of 0
      # until new child records are created or destroyed, causing silent
      # data inconsistency.
      #
      # Positive examples (violations):
      #   # Model adds counter_cache but no migration resets counters
      #   belongs_to :post, counter_cache: true
      #
      # Negative examples (compliant):
      #   # Migration includes reset_counters or update_counters
      #   Post.find_each { |p| Post.reset_counters(p.id, :comments) }
      class Ar006CounterCacheBackfill < Base
        ID = "AR006"
        CATEGORY = :active_record
        SEVERITY = :high
        RAILS_VERSIONS = [">= 4.0"].freeze
        CONFIDENCE_FLOOR = 0.80

        # Matches belongs_to with counter_cache option enabled.
        # Captures both `counter_cache: true` and `counter_cache: :custom_column`.
        COUNTER_CACHE_PATTERN = /belongs_to\s+:\w+.*counter_cache:\s*(?:true|:\w+)/

        # Patterns that indicate a proper backfill in a migration file.
        # Any of these in the changeset suggests the developer handled it.
        BACKFILL_PATTERNS = [
          /reset_counters/,
          /update_counters/,
          /update_all\b.*_count/,
          /update_columns?\b.*_count/,
          /Counter.*reset/i,
          /backfill/i,
          /_count\s*=\s*/
        ].freeze

        class << self
          # Applies when the diff includes changed model or migration files.
          #
          # @param diff_data [Hash] parsed diff information with :files key
          # @return [Boolean]
          def applies_to?(diff_data)
            return false unless diff_data.is_a?(Hash)

            files = diff_data[:files] || diff_data["files"] || []
            files.any? { |f| model_file?(f) || migration_file?(f) }
          end

          # Returns the prompt module text for LLM evaluation.
          #
          # @return [String]
          def prompt_module
            <<~PROMPT
              ## Rule AR006 — counter_cache Without Backfill

              **Severity:** high
              **Category:** active_record

              ### What to look for

              Detect `counter_cache: true` (or `counter_cache: :custom_column`)
              added to a `belongs_to` association in a model file, where the
              changeset does NOT include a corresponding data migration that
              backfills existing counter values.

              Without a backfill migration, all existing parent records will
              report a count of 0 for the cached counter column. This causes
              silent data inconsistency — views, APIs, and queries relying on
              the counter column will return incorrect results until each
              parent's counter is individually reset by a new child
              create/destroy event.

              ### Backfill patterns that make this compliant

              Any of the following in a migration within the same changeset:

              - `Model.reset_counters(id, :association)`
              - `Model.update_counters(id, column: value)`
              - `Model.update_all("comments_count = ...")`
              - SQL or Ruby code that explicitly sets `_count` columns
              - A migration or rake task file with "backfill" in its name or body

              ### What is acceptable

              - `counter_cache: true` added alongside a migration that resets or
                backfills the counter column.
              - `counter_cache: true` on a brand-new model with no existing data.
              - Changes that only modify an existing counter_cache (e.g. renaming
                the column) if the backfill is already in place.

              ### Output format

              For each finding, report:
              - file path and line number
              - the offending `belongs_to` line
              - whether a backfill migration was found in the changeset
              - suggested fix (add a data migration calling `reset_counters`)
            PROMPT
          end

          # Validates a finding against the diff data to reduce false positives.
          #
          # A finding is valid when:
          # 1. The file is a model file present in the diff
          # 2. The file contains a counter_cache declaration
          # 3. No backfill pattern exists anywhere in the changeset
          #
          # @param finding  [Hash] the LLM-generated finding
          # @param diff_data [Hash] parsed diff information
          # @return [Boolean]
          def validate(finding, diff_data)
            return false unless finding.is_a?(Hash) && diff_data.is_a?(Hash)

            file = finding[:file] || finding["file"]
            return false if file.nil? || file.empty?

            # Must be a model file
            return false unless model_file?(file)

            # Must be in the diff
            files = diff_data[:files] || diff_data["files"] || []
            return false unless files.any? { |f| normalize_path(f) == normalize_path(file) }

            # The model file must contain a counter_cache declaration
            file_entry = files.find { |f| normalize_path(f) == normalize_path(file) }
            content = extract_content(file_entry)
            return false unless content.match?(COUNTER_CACHE_PATTERN)

            # Check if any file in the changeset has a backfill pattern
            !changeset_has_backfill?(files)
          end

          private

          # Determines if a file path looks like a Rails model.
          #
          # @param file [String, Hash] file path string or hash with :path key
          # @return [Boolean]
          def model_file?(file)
            path = normalize_path(file)
            return false if path.nil?

            path.match?(%r{app/models/.*\.rb\z})
          end

          # Determines if a file path looks like a Rails migration.
          #
          # @param file [String, Hash] file path string or hash with :path key
          # @return [Boolean]
          def migration_file?(file)
            path = normalize_path(file)
            return false if path.nil?

            path.match?(%r{db/migrate/.*\.rb\z})
          end

          # Checks all files in the changeset for backfill patterns.
          #
          # @param files [Array<Hash, String>] list of changed files
          # @return [Boolean]
          def changeset_has_backfill?(files)
            files.any? do |f|
              content = extract_content(f)
              next false if content.empty?

              BACKFILL_PATTERNS.any? { |pattern| content.match?(pattern) }
            end
          end

          # Extracts text content from a file entry.
          #
          # @param file [Hash, String]
          # @return [String]
          def extract_content(file)
            case file
            when Hash
              file[:content] || file["content"] || file[:patch] || file["patch"] || ""
            else
              ""
            end
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

RubynCode::Rules::Registry.register(RubynCode::Rules::ActiveRecord::Ar006CounterCacheBackfill)
