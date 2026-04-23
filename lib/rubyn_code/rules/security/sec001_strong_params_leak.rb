# frozen_string_literal: true

module RubynCode
  module Rules
    module Security
      # SEC001 — Strong Parameters Nested Leak
      #
      # Detects permit! or overly broad permit calls that allow nested
      # attributes to leak through. Common examples:
      #
      #   params.permit!                           # permits everything
      #   params.require(:user).permit!            # permits all user attrs
      #   params.require(:user).permit(:name, :email, user_attributes: {})
      #   params.require(:user).permit(:name, role_ids: [])
      #
      # These patterns bypass Rails' mass-assignment protection and can
      # expose admin flags, role assignments, or other privileged fields
      # to user-controlled input.
      class Sec001StrongParamsLeak < Base
        ID = 'SEC001'
        CATEGORY = :security
        SEVERITY = :high
        RAILS_VERSIONS = ['>= 4.0'].freeze
        CONFIDENCE_FLOOR = 0.85

        # Matches params.permit! anywhere in the line
        PERMIT_BANG_PATTERN = /\.permit!/

        # Matches nested attribute hashes in permit calls:
        #   permit(:name, user_attributes: {})
        #   permit(:name, user_attributes: [:id, :admin])
        #   permit(:name, profile_attributes: %i[bio avatar])
        NESTED_ATTRIBUTES_PATTERN = /\.permit\(.*\w+_attributes:\s*[\[{%]/m

        # Matches permit calls that include _ids arrays, which can
        # manipulate has_many :through associations:
        #   permit(:name, role_ids: [])
        #   permit(:name, tag_ids: [])
        ASSOCIATION_IDS_PATTERN = /\.permit\(.*\w+_ids:\s*\[/m

        # Matches permit calls with deeply nested hash permissions:
        #   permit(user: [:name, { address: [:street] }])
        #   permit(user: {})
        DEEP_NESTED_PATTERN = /\.permit\(.*\w+:\s*\{/m

        PATTERNS = [
          PERMIT_BANG_PATTERN,
          NESTED_ATTRIBUTES_PATTERN,
          ASSOCIATION_IDS_PATTERN,
          DEEP_NESTED_PATTERN
        ].freeze

        class << self
          # Applies to changed controller files only.
          #
          # @param diff_data [Hash] :files => Array<Hash{ path: }>
          # @return [Boolean]
          def applies_to?(diff_data)
            return false unless diff_data.is_a?(Hash)

            files = diff_data.fetch(:files, [])
            files.any? { |f| controller_file?(f[:path]) }
          end

          # Returns the prompt module text for LLM evaluation.
          #
          # @return [String]
          def prompt_module
            <<~PROMPT
              ## Rule SEC001 — Strong Parameters Nested Leak

              **Severity:** high
              **Category:** security

              ### What to look for

              Detect any of the following patterns in controller code:

              1. **`permit!`** — Permits ALL parameters without restriction. This is
                 almost never acceptable in production code. It bypasses Rails'
                 strong parameters entirely.

              2. **Nested `_attributes` in permit** — When a `permit` call includes
                 keys ending in `_attributes:` with a hash or array value, nested
                 model attributes are exposed to mass assignment. An attacker could
                 inject fields like `admin`, `role`, or `verified` into the nested
                 attributes.

              3. **Association `_ids` arrays in permit** — Permitting `role_ids: []`
                 or `tag_ids: []` allows the client to manipulate has_many :through
                 associations, potentially escalating privileges.

              4. **Deep nested hash permissions** — Permitting a key with an empty
                 hash `{}` value (e.g., `permit(user: {})`) allows all nested
                 attributes for that key.

              ### What is acceptable

              - Flat `permit(:name, :email, :bio)` calls with only scalar attributes.
              - Permit calls in test helpers or factories.
              - Permit calls guarded by explicit attribute whitelists that do not
                include privileged fields.

              ### Output format

              For each finding, report:
              - file path and line number
              - the offending code snippet
              - which sub-pattern was matched (permit!, nested_attributes, association_ids, deep_nested)
              - suggested fix
            PROMPT
          end

          # Validates a finding against the diff data to reduce false positives.
          #
          # @param finding  [Hash] the LLM-generated finding
          # @param diff_data [Hash] :files => Array<Hash{ path: }>
          # @return [Boolean]
          def validate(finding, diff_data)
            return false unless finding.is_a?(Hash) && diff_data.is_a?(Hash)

            file_path = extract_file_path(finding)
            return false unless file_path
            return false unless controller_file?(file_path)
            return false unless file_in_diff?(file_path, diff_data)

            snippet_matches_pattern?(finding)
          end

          private

          # Extracts the file path string from a finding hash.
          #
          # @param finding [Hash] :file or "file" key
          # @return [String, nil]
          def extract_file_path(finding)
            path = finding[:file] || finding['file']
            return nil if path.nil? || path.empty?

            path
          end

          # Checks whether the given file path appears in the diff file list.
          #
          # @param file_path [String]
          # @param diff_data [Hash] :files => Array<Hash{ path: }>
          # @return [Boolean]
          def file_in_diff?(file_path, diff_data)
            files = diff_data.fetch(:files, [])
            files.any? { |f| f[:path] == file_path }
          end

          # Checks whether the finding's snippet matches any known pattern.
          # Joins multiline snippets before matching to handle cases where
          # permit calls span multiple lines.
          #
          # @param finding [Hash] :snippet or "snippet" key
          # @return [Boolean]
          def snippet_matches_pattern?(finding)
            snippet = finding[:snippet] || finding['snippet'] || ''
            collapsed = snippet.gsub(/\s*\n\s*/, ' ')

            PATTERNS.any? { |pattern| snippet.match?(pattern) || collapsed.match?(pattern) }
          end

          # Checks whether a file path looks like a Rails controller.
          #
          # @param path [String]
          # @return [Boolean]
          def controller_file?(path)
            return false unless path

            path.match?(%r{app/controllers/.*_controller\.rb\z})
          end
        end
      end
    end
  end
end

RubynCode::Rules::Registry.register(RubynCode::Rules::Security::Sec001StrongParamsLeak)
