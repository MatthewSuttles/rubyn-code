# frozen_string_literal: true

module RubynCode
  module Rules
    module Security
      # SEC002 — Pundit Scope Not Applied on Index
      #
      # Detects controller index actions that query ActiveRecord models without
      # wrapping the query in `policy_scope`, allowing users to see records they
      # should not have access to.
      #
      # Positive examples (violations):
      #   def index
      #     @posts = Post.all          # missing policy_scope
      #   end
      #
      # Negative examples (compliant):
      #   def index
      #     @posts = policy_scope(Post) # properly scoped
      #   end
      class Sec002PunditScopeMissing < Base
        ID = "SEC002"
        CATEGORY = :security
        SEVERITY = :high
        RAILS_VERSIONS = [">= 5.0"].freeze
        CONFIDENCE_FLOOR = 0.85

        # Patterns that indicate an unscoped collection query inside an action.
        UNSCOPED_QUERY_PATTERN = /
          \.(all|where|order|includes|joins|left_joins|eager_load|preload|
             find_by_sql|select|group|having|distinct|limit|offset|
             from|reorder|rewhere|none|unscoped)\b
        /x.freeze

        # Pattern matching a `policy_scope(...)` or `policy_scope Model` call.
        # Accepts either parentheses or whitespace after `policy_scope`.
        POLICY_SCOPE_PATTERN = /policy_scope[\s(]/

        # Pattern to detect `index` action definitions.
        # Anchored to reject commented-out definitions (e.g. `# def index`).
        INDEX_ACTION_PATTERN = /\A\s*def\s+index\b/

        class << self
          # Applies when the diff touches a controller file in a project that
          # uses the Pundit gem.
          #
          # @param diff_data [Hash] :files, :gemfile_content
          # @return [Boolean]
          def applies_to?(diff_data)
            return false unless pundit_present?(diff_data)

            changed_files = diff_data[:files] || []
            changed_files.any? { |f| controller_file?(f[:path] || f[:name].to_s) }
          end

          # Returns the LLM prompt module for evaluating this rule.
          #
          # @return [String]
          def prompt_module
            <<~PROMPT
              Rule SEC002 — Pundit Scope Not Applied on Index

              Severity: high
              Category: security

              ## What to look for
              Controller `index` actions that query ActiveRecord models without
              wrapping the query in `policy_scope`. This allows users to see
              records they shouldn't have access to.

              ## Violation patterns
              - `Model.all`, `Model.where(...)`, `Model.order(...)` etc. in an
                index action without a corresponding `policy_scope(Model)` call.
              - Assigning a raw scope to an instance variable:
                `@records = Record.where(active: true)`

              ## Compliant patterns
              - `@records = policy_scope(Record)`
              - `@records = policy_scope(Record).where(active: true)`
              - `@records = policy_scope(Record.where(active: true))`
              - Non-index actions (show, edit, etc.) are out of scope for this rule.
              - Actions that don't query models at all.

              ## Output
              For each violation found, return:
              - file path
              - line number
              - the offending code snippet
              - suggested fix using `policy_scope`
            PROMPT
          end

          # Validates a finding by checking the diff confirms an unscoped query
          # exists in an index action without policy_scope.
          #
          # @param finding  [Hash] :file, :line, :snippet
          # @param diff_data [Hash] :files
          # @return [Boolean]
          def validate(finding, diff_data)
            file_path = finding[:file] || finding["file"]
            return false unless file_path && controller_file?(file_path)

            file_entry = find_file(diff_data, file_path)
            return false unless file_entry

            content = file_entry[:content] || file_entry[:patch] || ""
            return false if content.empty?

            index_bodies = extract_index_bodies(content)
            return false if index_bodies.empty?

            index_bodies.any? do |body|
              has_unscoped_query?(body) && !has_policy_scope?(body)
            end
          end

          private

          # Checks whether the project uses Pundit.
          def pundit_present?(diff_data)
            gemfile = diff_data[:gemfile_content] || ""
            gemfile_lock = diff_data[:gemfile_lock_content] || ""

            return true if gemfile.match?(/gem\s+['"]pundit['"]/)
            return true if gemfile_lock.match?(/pundit\s/)

            # Fall back: check if any changed file includes Pundit
            files = diff_data[:files] || []
            files.any? do |f|
              content = f[:content] || f[:patch] || ""
              content.match?(/include\s+Pundit/) || content.match?(/Pundit::/)
            end
          end

          # Determines if a file path looks like a Rails controller.
          def controller_file?(path)
            path.match?(%r{app/controllers/.*_controller\.rb\z})
          end

          # Locates a file entry in diff_data by path.
          def find_file(diff_data, file_path)
            files = diff_data[:files] || []
            files.find do |f|
              (f[:path] || f[:name].to_s) == file_path
            end
          end

          # Extracts the body text of each `def index` method from the content.
          # Uses simple indentation-based parsing — finds `def index` and
          # collects lines until the matching `end` at the same indent level.
          def extract_index_bodies(content)
            lines = content.lines
            bodies = []
            i = 0

            while i < lines.length
              line = lines[i]
              if line.match?(INDEX_ACTION_PATTERN)
                indent = line[/\A\s*/].length
                body_lines = []
                i += 1
                while i < lines.length
                  current = lines[i]
                  current_indent = current.strip.empty? ? indent + 1 : current[/\A\s*/].length
                  break if current.strip == "end" && current_indent == indent

                  body_lines << current
                  i += 1
                end
                bodies << body_lines.join
              end
              i += 1
            end

            bodies
          end

          # Checks if the body contains an unscoped ActiveRecord query.
          def has_unscoped_query?(body)
            body.match?(UNSCOPED_QUERY_PATTERN)
          end

          # Checks if the body contains a `policy_scope` call.
          def has_policy_scope?(body)
            body.match?(POLICY_SCOPE_PATTERN)
          end
        end
      end
    end
  end
end

RubynCode::Rules::Registry.register(RubynCode::Rules::Security::Sec002PunditScopeMissing)
