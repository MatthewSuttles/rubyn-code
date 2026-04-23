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
        ID = "SEC001"
        CATEGORY = :security
        SEVERITY = :high
        RAILS_VERSIONS = [">= 4.0"].freeze
        CONFIDENCE_FLOOR = 0.85

        # Matches params.permit! anywhere in the line
        PERMIT_BANG_PATTERN = /\.permit!/

        # Matches nested attribute hashes in permit calls:
        #   permit(:name, user_attributes: {})
        #   permit(:name, user_attributes: [:id, :admin])
        #   permit(:name, profile_attributes: %i[bio avatar])
        NESTED_ATTRIBUTES_PATTERN = /\.permit\(.*\w+_attributes:\s*[\[{%]/

        # Matches permit calls that include _ids arrays, which can
        # manipulate has_many :through associations:
        #   permit(:name, role_ids: [])
        #   permit(:name, tag_ids: [])
        ASSOCIATION_IDS_PATTERN = /\.permit\(.*\w+_ids:\s*\[/

        # Matches permit calls with deeply nested hash permissions:
        #   permit(user: [:name, { address: [:street] }])
        #   permit(user: {})
        DEEP_NESTED_PATTERN = /\.permit\(.*\w+:\s*\{/

        PATTERNS = [
          PERMIT_BANG_PATTERN,
          NESTED_ATTRIBUTES_PATTERN,
          ASSOCIATION_IDS_PATTERN,
          DEEP_NESTED_PATTERN
        ].freeze

        class << self
          # Applies to changed controller files only.
          #
          # @param diff_data [Hash] parsed diff information with :files key
          # @return [Boolean]
          def applies_to?(diff_data)
            return false unless diff_data.is_a?(Hash)

            files = diff_data[:files] || diff_data["files"] || []
            files.any? { |f| controller_file?(f) }
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
          # @param diff_data [Hash] parsed diff information
          # @return [Boolean]
          def validate(finding, diff_data)
            return false unless finding.is_a?(Hash) && diff_data.is_a?(Hash)

            file = finding[:file] || finding["file"]
            return false if file.nil? || file.empty?

            # Must be a controller file
            return false unless controller_file?(file)

            # Check that the file is in the diff
            files = diff_data[:files] || diff_data["files"] || []
            return false unless files.any? { |f| normalize_path(f) == normalize_path(file) }

            # Check that the snippet contains one of our patterns
            snippet = finding[:snippet] || finding["snippet"] || ""
            PATTERNS.any? { |pattern| snippet.match?(pattern) }
          end

          private

          # Determines if a file path looks like a Rails controller.
          #
          # @param file [String, Hash] file path string or hash with :path key
          # @return [Boolean]
          def controller_file?(file)
            path = normalize_path(file)
            return false if path.nil?

            path.match?(%r{app/controllers/.*_controller\.rb\z}) ||
              path.match?(%r{controllers/.*_controller\.rb\z})
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

RubynCode::Rules::Registry.register(RubynCode::Rules::Security::Sec001StrongParamsLeak)
