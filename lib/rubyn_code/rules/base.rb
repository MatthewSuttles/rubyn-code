# frozen_string_literal: true

module RubynCode
  module Rules
    # Abstract base class for all Rubyn rules.
    #
    # Subclasses must define:
    #   ID               - unique rule identifier (e.g. "AR001")
    #   CATEGORY         - rule category (e.g. :active_record, :callbacks)
    #   SEVERITY         - one of :critical, :high, :medium, :low
    #   RAILS_VERSIONS   - array of supported Rails version ranges (e.g. [">= 6.0"])
    #   CONFIDENCE_FLOOR - minimum confidence threshold (0.0..1.0)
    #
    # Subclasses should override the class methods below. Each raises
    # NotImplementedError by default to enforce the contract.
    class Base
      ID = nil
      CATEGORY = nil
      SEVERITY = nil
      RAILS_VERSIONS = [].freeze
      CONFIDENCE_FLOOR = 0.0

      class << self
        def id
          const_get(:ID)
        end

        def category
          const_get(:CATEGORY)
        end

        def severity
          const_get(:SEVERITY)
        end

        def rails_versions
          const_get(:RAILS_VERSIONS)
        end

        def confidence_floor
          const_get(:CONFIDENCE_FLOOR)
        end

        # Determines whether this rule is relevant to the given diff data.
        #
        # @param _diff_data [Hash] parsed diff information
        # @return [Boolean]
        def applies_to?(_diff_data)
          raise NotImplementedError, "#{name}.applies_to? must be implemented"
        end

        # Returns the prompt module (text or template) used by the LLM to
        # evaluate this rule against a diff.
        #
        # @return [String]
        def prompt_module
          raise NotImplementedError, "#{name}.prompt_module must be implemented"
        end

        # Validates a finding returned by the LLM against the original diff
        # data to filter out false positives.
        #
        # @param _finding  [Hash] the LLM-generated finding
        # @param _diff_data [Hash] parsed diff information
        # @return [Boolean]
        def validate(_finding, _diff_data)
          raise NotImplementedError, "#{name}.validate must be implemented"
        end
      end
    end
  end
end
