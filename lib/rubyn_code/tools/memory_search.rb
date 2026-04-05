# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class MemorySearch < Base
      TOOL_NAME = 'memory_search'
      DESCRIPTION = 'Searches project memories using full-text search. ' \
                    'Returns relevant memories including code patterns, user preferences, ' \
                    'project conventions, error resolutions, and past decisions.'
      PARAMETERS = {
        query: { type: :string, required: true, description: 'Search query for finding relevant memories' },
        tier: { type: :string, required: false, description: 'Filter by memory tier: short, medium, or long' },
        category: { type: :string, required: false,
                    description: 'Filter by category: code_pattern, user_preference, ' \
                                 'project_convention, error_resolution, or decision' },
        limit: { type: :integer, required: false, description: 'Maximum number of results to return (default 10)' }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      # @param project_root [String]
      # @param memory_search [Memory::Search] injected search instance
      def initialize(project_root:, memory_search: nil)
        super(project_root: project_root)
        @memory_search = memory_search
      end

      # @param query [String]
      # @param tier [String, nil]
      # @param category [String, nil]
      # @param limit [Integer, nil]
      # @return [String] formatted search results
      def execute(query:, tier: nil, category: nil, limit: 10)
        search = @memory_search || resolve_memory_search
        results = search.search(query, tier: tier, category: category, limit: limit.to_i)

        return "No memories found for query: #{query}" if results.empty?

        format_results(results)
      end

      private

      # Formats an array of MemoryRecord into a human-readable string.
      #
      # @param records [Array<Memory::MemoryRecord>]
      # @return [String]
      def format_results(records)
        lines = ["Found #{records.size} memor#{records.size == 1 ? 'y' : 'ies'}:\n"]
        records.each_with_index { |record, idx| lines.concat(format_single_memory(record, idx)) }
        lines.join("\n")
      end

      def format_single_memory(record, idx)
        [
          "--- Memory #{idx + 1} ---",
          "ID: #{record.id}",
          "Tier: #{record.tier} | Category: #{record.category || 'none'}",
          "Relevance: #{format('%.2f', record.relevance_score)} | Accessed: #{record.access_count} times",
          "Created: #{record.created_at}",
          '', record.content, ''
        ]
      end

      # Lazily resolves a Memory::Search instance from the project root.
      #
      # @return [Memory::Search]
      def resolve_memory_search
        db = DB::Connection.instance
        Memory::Search.new(db, project_path: project_root)
      end
    end

    Registry.register(MemorySearch)
  end
end
