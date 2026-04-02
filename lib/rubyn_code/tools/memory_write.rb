# frozen_string_literal: true

require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class MemoryWrite < Base
      TOOL_NAME = "memory_write"
      DESCRIPTION = "Writes a new memory to the project memory store. " \
                    "Use this to persist code patterns, user preferences, project conventions, " \
                    "error resolutions, or architectural decisions for future reference."
      PARAMETERS = {
        content: { type: :string, required: true, description: "The memory content to store" },
        tier: { type: :string, required: false, description: "Memory retention tier: short, medium (default), or long" },
        category: { type: :string, required: false, description: "Category: code_pattern, user_preference, project_convention, error_resolution, or decision" }
      }.freeze
      RISK_LEVEL = :read  # Memory is internal — no user approval needed

      # @param project_root [String]
      # @param memory_store [Memory::Store] injected store instance
      def initialize(project_root:, memory_store: nil)
        super(project_root: project_root)
        @memory_store = memory_store
      end

      # @param content [String]
      # @param tier [String] defaults to "medium"
      # @param category [String, nil]
      # @return [String] confirmation message
      def execute(content:, tier: "medium", category: nil)
        store = @memory_store || resolve_memory_store
        record = store.write(content: content, tier: tier, category: category)

        "Memory saved (ID: #{record.id}, tier: #{record.tier}" \
          "#{record.category ? ", category: #{record.category}" : ''})."
      end

      private

      # Lazily resolves a Memory::Store instance from the project root.
      #
      # @return [Memory::Store]
      def resolve_memory_store
        db = DB::Connection.instance
        Memory::Store.new(db, project_path: project_root)
      end
    end

    Registry.register(MemoryWrite)
  end
end
