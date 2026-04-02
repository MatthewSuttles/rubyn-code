# frozen_string_literal: true

module RubynCode
  module Memory
    VALID_TIERS = %w[short medium long].freeze
    VALID_CATEGORIES = %w[code_pattern user_preference project_convention error_resolution decision].freeze

    # Immutable value object representing a single memory record.
    #
    # Tiers control retention and decay:
    #   - "short"  : ephemeral, decays quickly, session-scoped
    #   - "medium" : moderate retention, project-scoped
    #   - "long"   : persistent, rarely decays
    #
    # Categories classify the kind of knowledge stored:
    #   - "code_pattern"        : recurring code patterns or idioms
    #   - "user_preference"     : how the user likes things done
    #   - "project_convention"  : project-specific conventions
    #   - "error_resolution"    : known error/fix pairs
    #   - "decision"            : architectural or design decisions
    MemoryRecord = Data.define(
      :id, :project_path, :tier, :category, :content,
      :relevance_score, :access_count, :last_accessed_at,
      :expires_at, :metadata, :created_at
    ) do
      # @return [Boolean]
      def expired?
        return false if expires_at.nil?

        Time.parse(expires_at.to_s) < Time.now
      rescue ArgumentError
        false
      end

      # @return [Boolean]
      def short? = tier == "short"

      # @return [Boolean]
      def medium? = tier == "medium"

      # @return [Boolean]
      def long? = tier == "long"

      # @return [Hash]
      def to_h
        {
          id: id,
          project_path: project_path,
          tier: tier,
          category: category,
          content: content,
          relevance_score: relevance_score,
          access_count: access_count,
          last_accessed_at: last_accessed_at,
          expires_at: expires_at,
          metadata: metadata,
          created_at: created_at
        }
      end
    end
  end
end
