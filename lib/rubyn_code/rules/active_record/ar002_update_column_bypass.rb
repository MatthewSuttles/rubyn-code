# frozen_string_literal: true

module RubynCode
  module Rules
    module ActiveRecord
      # AR002 — update_column Bypasses Validations
      #
      # Detects usage of update_column, update_columns, and update_all that
      # bypasses ActiveRecord validations and callbacks. These methods write
      # directly to the database, skipping model-layer protections.
      #
      # Positive examples (violations):
      #   user.update_column(:email, "new@example.com")
      #   user.update_columns(name: "Bob", admin: true)
      #   User.where(active: false).update_all(deleted_at: Time.current)
      #   User.update_all("admin = true")
      #
      # Negative examples (compliant):
      #   user.update(email: "new@example.com")
      #   user.update!(name: "Bob")
      #   User.where(active: false).update_all  # no args — won't match
      #   user.save
      class Ar002UpdateColumnBypass < Base
        ID = "AR002"
        CATEGORY = :active_record
        SEVERITY = :high
        RAILS_VERSIONS = [">= 4.0"].freeze
        CONFIDENCE_FLOOR = 0.85

        # Matches update_column( — single column bypass.
        # Handles both explicit receiver (obj.update_column) and implicit self.
        # Uses word boundary to avoid matching update_column_widths etc.
        UPDATE_COLUMN_PATTERN = /(?:^|\.\s*|\s)update_column\s*\(/

        # Matches update_columns( — multi-column bypass.
        UPDATE_COLUMNS_PATTERN = /(?:^|\.\s*|\s)update_columns\s*\(/

        # Matches update_all( — bulk bypass on a scope/class.
        UPDATE_ALL_PATTERN = /\.update_all\s*\(/

        PATTERNS = [
          UPDATE_COLUMN_PATTERN,
          UPDATE_COLUMNS_PATTERN,
          UPDATE_ALL_PATTERN
        ].freeze

        class << self
          # Applies when any changed .rb file lives under app/.
          #
          # @param diff_data [Hash] parsed diff information with :files key
          # @return [Boolean]
          def applies_to?(diff_data)
            return false unless diff_data.is_a?(Hash)

            files = diff_data[:files] || diff_data["files"] || []
            files.any? { |f| app_ruby_file?(f) }
          end

          # Returns the prompt module text for LLM evaluation.
          #
          # @return [String]
          def prompt_module
            <<~PROMPT
              ## Rule AR002 — update_column Bypasses Validations

              **Severity:** high
              **Category:** active_record

              ### What to look for

              Detect any of the following methods in application code:

              1. **`update_column`** — Updates a single attribute directly in the
                 database, bypassing all ActiveRecord validations, callbacks, and
                 `updated_at` timestamping. The record's in-memory state is updated
                 but no model-layer protections run.

              2. **`update_columns`** — Same as `update_column` but accepts a hash
                 of multiple attributes. All the same bypass concerns apply.

              3. **`update_all`** — Performs a bulk SQL UPDATE on a scope or model
                 class. No validations, callbacks, or individual record instantiation
                 occurs. While sometimes necessary for performance, it should be
                 flagged for review.

              ### Why this matters

              Bypassing validations can lead to:
              - Invalid data persisted to the database
              - Skipped audit callbacks (e.g., paper_trail, logidze)
              - Skipped after_save hooks that maintain derived state
              - Security-relevant callbacks being ignored (e.g., role checks)

              ### What is acceptable

              - Safe update methods: `update`, `update!`, `save`, `save!`
              - Usage in migrations (detected via file path)
              - Usage in rake tasks or data migration scripts when documented
              - Test files where bypass is intentional

              ### Output format

              For each finding, report:
              - file path and line number
              - the offending code snippet
              - which method was used (update_column, update_columns, update_all)
              - suggested fix using safe update methods
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

            # Must be an app/ Ruby file
            return false unless app_ruby_file?(file)

            # Check that the file is in the diff
            files = diff_data[:files] || diff_data["files"] || []
            return false unless files.any? { |f| normalize_path(f) == normalize_path(file) }

            # Check that the snippet contains one of our patterns
            snippet = finding[:snippet] || finding["snippet"] || ""
            PATTERNS.any? { |pattern| snippet.match?(pattern) }
          end

          private

          # Determines if a file path is a Ruby file under app/.
          #
          # @param file [String, Hash] file path string or hash with :path key
          # @return [Boolean]
          def app_ruby_file?(file)
            path = normalize_path(file)
            return false if path.nil?

            path.match?(%r{app/.*\.rb\z})
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

RubynCode::Rules::Registry.register(RubynCode::Rules::ActiveRecord::Ar002UpdateColumnBypass)
