# frozen_string_literal: true

module RubynCode
  module Teams
    # Immutable value object representing a teammate in an agent team.
    #
    # Status values: "idle", "active", "offline"
    VALID_STATUSES = %w[idle active offline].freeze

    Teammate = Data.define(
      :id, :name, :role, :persona, :model, :status, :metadata, :created_at
    ) do

      # @return [Boolean]
      def idle? = status == "idle"

      # @return [Boolean]
      def active? = status == "active"

      # @return [Boolean]
      def offline? = status == "offline"

      # @return [Hash]
      def to_h
        {
          id: id,
          name: name,
          role: role,
          persona: persona,
          model: model,
          status: status,
          metadata: metadata,
          created_at: created_at
        }
      end
    end
  end
end
