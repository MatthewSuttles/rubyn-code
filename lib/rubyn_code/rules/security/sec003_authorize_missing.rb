# frozen_string_literal: true

module RubynCode
  module Rules
    module Security
      # SEC003 — Authorize Call Missing
      #
      # Detects controller actions (show, update, destroy) that load a record
      # via a finder method but never call `authorize(@record)`. This is a
      # common source of broken access control in apps that use Pundit.
      #
      # Applies to changed controller files in projects that include Pundit.
      class Sec003AuthorizeMissing < Base
        ID               = "SEC003"
        CATEGORY         = :security
        SEVERITY         = :high
        RAILS_VERSIONS   = [">= 5.0"].freeze
        CONFIDENCE_FLOOR = 0.85

        # Record-loading patterns: find, find_by, find_by!, where(...).first, etc.
        FINDER_PATTERN = /
          \.(find|find_by!?|find_sole_by|where)\b
        /x

        # Authorize call pattern: authorize(@var) or authorize(var)
        AUTHORIZE_PATTERN = /
          \bauthorize\s*\(
        /x

        # Actions that typically require authorization on a loaded record.
        GUARDED_ACTIONS = %w[show edit update destroy].freeze

        ACTION_DEF_PATTERN = /
          \bdef\s+(#{GUARDED_ACTIONS.join('|')})\b
        /x

        class << self
          # Applies when the diff includes controller files and the project
          # uses Pundit (detected via Gemfile or include Pundit in a controller).
          #
          # @param diff_data [Hash] :files => Array<Hash{ path:, patch: }>
          #   optionally :gemfile_content => String
          # @return [Boolean]
          def applies_to?(diff_data)
            files = diff_data.fetch(:files, [])
            has_controller_changes = files.any? { |f| controller_file?(f[:path]) }
            return false unless has_controller_changes

            uses_pundit?(diff_data)
          end

          # Returns the prompt text used by the LLM to evaluate this rule.
          #
          # @return [String]
          def prompt_module
            <<~PROMPT
              ## SEC003 — Authorize Call Missing

              **Goal:** Identify controller actions that load a record but never
              call `authorize` on it.

              **Scope:** Actions named `show`, `edit`, `update`, or `destroy` in
              Rails controllers that use Pundit.

              **Detection logic:**
              1. Find each action definition (`def show`, `def update`, etc.).
              2. Check if the action body contains a record-loading call
                 (e.g. `find`, `find_by`, `find_by!`, `where(...).first`).
              3. Check if the action body also contains an `authorize(...)` call.
              4. Flag the action if it loads a record but does NOT authorize.

              **Ignore:**
              - Actions that only render collections (index).
              - Actions behind `before_action :authorize_*` filters — these are
                handled at a different layer and should not be flagged here.
              - Private/protected methods (only public action definitions).

              **Output one finding per flagged action** with:
              - file path
              - action name
              - line number of the action definition
              - brief explanation
            PROMPT
          end

          # Validates a finding against the raw diff to reduce false positives.
          #
          # @param finding  [Hash] :file, :action, :line
          # @param diff_data [Hash] :files => Array<Hash{ path:, patch: }>
          # @return [Boolean]
          def validate(finding, diff_data)
            file_path = finding[:file] || finding["file"]
            action    = finding[:action] || finding["action"]
            return false unless file_path && action

            file_entry = diff_data.fetch(:files, []).find { |f| f[:path] == file_path }
            return false unless file_entry

            content = file_entry[:content] || file_entry[:patch] || ""
            action_body = extract_action_body(content, action)
            return false unless action_body

            has_finder    = action_body.match?(FINDER_PATTERN)
            no_authorize  = !action_body.match?(AUTHORIZE_PATTERN)

            has_finder && no_authorize
          end

          private

          # Checks whether a file path looks like a Rails controller.
          #
          # @param path [String]
          # @return [Boolean]
          def controller_file?(path)
            return false unless path

            path.match?(%r{app/controllers/.*_controller\.rb\z})
          end

          # Detects Pundit usage via Gemfile content or controller includes.
          #
          # @param diff_data [Hash]
          # @return [Boolean]
          def uses_pundit?(diff_data)
            gemfile = diff_data[:gemfile_content] || ""
            return true if gemfile.match?(/['"]pundit['"]/)

            files = diff_data.fetch(:files, [])
            files.any? do |f|
              content = f[:content] || f[:patch] || ""
              content.match?(/\binclude\s+Pundit\b/) ||
                content.match?(/\bPundit\b/)
            end
          end

          # Extracts the body of a specific action method from file content.
          # Uses simple indentation-based parsing (good enough for validation).
          #
          # @param content [String] full file content
          # @param action_name [String] the method name to extract
          # @return [String, nil] the method body or nil if not found
          def extract_action_body(content, action_name)
            lines = content.lines
            start_index = nil
            base_indent = nil

            lines.each_with_index do |line, idx|
              if line.match?(/\bdef\s+#{Regexp.escape(action_name)}\b/)
                start_index = idx
                base_indent = line[/\A(\s*)/, 1].length
                break
              end
            end

            return nil unless start_index

            body_lines = [lines[start_index]]
            ((start_index + 1)...lines.length).each do |idx|
              line = lines[idx]
              # End of method: a line at the same or lesser indentation starting with `end`
              if line.match?(/\A\s{0,#{base_indent}}end\b/)
                body_lines << line
                break
              end
              body_lines << line
            end

            body_lines.join
          end
        end
      end
    end
  end
end

RubynCode::Rules::Registry.register(RubynCode::Rules::Security::Sec003AuthorizeMissing)
