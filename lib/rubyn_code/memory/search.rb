# frozen_string_literal: true

require 'json'

module RubynCode
  module Memory
    # Searches memories using SQLite FTS5 full-text search and standard
    # queries. Every search method automatically increments access_count
    # and updates last_accessed_at on returned records, reinforcing
    # frequently-accessed memories against decay.
    class Search
      # @param db [DB::Connection] database connection
      # @param project_path [String] scoping path for searches
      def initialize(db, project_path:)
        @db = db
        @project_path = project_path
      end

      # Full-text search across memory content using FTS5.
      #
      # @param query [String] the search query (FTS5 syntax supported)
      # @param tier [String, nil] filter by tier
      # @param category [String, nil] filter by category
      # @param limit [Integer] maximum results (default 10)
      # @return [Array<MemoryRecord>]
      def search(query, tier: nil, category: nil, limit: 10)
        conditions = ['m.project_path = ?']
        params = [@project_path]

        if tier
          conditions << 'm.tier = ?'
          params << tier
        end

        if category
          conditions << 'm.category = ?'
          params << category
        end

        params << query
        params << limit

        rows = @db.query(<<~SQL, params).to_a
          SELECT m.id, m.project_path, m.tier, m.category, m.content,
                 m.relevance_score, m.access_count, m.last_accessed_at,
                 m.expires_at, m.metadata, m.created_at
          FROM memories m
          WHERE #{conditions.join(' AND ')}
            AND m.content LIKE '%' || ? || '%'
          ORDER BY m.relevance_score DESC, m.created_at DESC
          LIMIT ?
        SQL

        records = rows.map { |row| build_record(row) }
        touch_accessed(records)
        records
      end

      # Returns the most recently created memories.
      #
      # @param limit [Integer] maximum results (default 10)
      # @return [Array<MemoryRecord>]
      def recent(limit: 10)
        rows = @db.query(<<~SQL, [@project_path, limit]).to_a
          SELECT id, project_path, tier, category, content,
                 relevance_score, access_count, last_accessed_at,
                 expires_at, metadata, created_at
          FROM memories
          WHERE project_path = ?
          ORDER BY created_at DESC
          LIMIT ?
        SQL

        records = rows.map { |row| build_record(row) }
        touch_accessed(records)
        records
      end

      # Returns memories filtered by category.
      #
      # @param category [String]
      # @param limit [Integer] maximum results (default 10)
      # @return [Array<MemoryRecord>]
      def by_category(category, limit: 10)
        rows = @db.query(<<~SQL, [@project_path, category, limit]).to_a
          SELECT id, project_path, tier, category, content,
                 relevance_score, access_count, last_accessed_at,
                 expires_at, metadata, created_at
          FROM memories
          WHERE project_path = ?
            AND category = ?
          ORDER BY relevance_score DESC, created_at DESC
          LIMIT ?
        SQL

        records = rows.map { |row| build_record(row) }
        touch_accessed(records)
        records
      end

      # Returns memories filtered by tier.
      #
      # @param tier [String]
      # @param limit [Integer] maximum results (default 10)
      # @return [Array<MemoryRecord>]
      def by_tier(tier, limit: 10)
        rows = @db.query(<<~SQL, [@project_path, tier, limit]).to_a
          SELECT id, project_path, tier, category, content,
                 relevance_score, access_count, last_accessed_at,
                 expires_at, metadata, created_at
          FROM memories
          WHERE project_path = ?
            AND tier = ?
          ORDER BY relevance_score DESC, created_at DESC
          LIMIT ?
        SQL

        records = rows.map { |row| build_record(row) }
        touch_accessed(records)
        records
      end

      private

      # Builds a MemoryRecord from a database row.
      #
      # @param row [Hash]
      # @return [MemoryRecord]
      def build_record(row)
        metadata = parse_json(row['metadata'])

        MemoryRecord.new(
          id: row['id'],
          project_path: row['project_path'],
          tier: row['tier'],
          category: row['category'],
          content: row['content'],
          relevance_score: row['relevance_score'].to_f,
          access_count: row['access_count'].to_i,
          last_accessed_at: row['last_accessed_at'],
          expires_at: row['expires_at'],
          metadata: metadata,
          created_at: row['created_at']
        )
      end

      # Increments access_count and updates last_accessed_at for all
      # returned records, reinforcing them against decay.
      #
      # @param records [Array<MemoryRecord>]
      # @return [void]
      def touch_accessed(records)
        return if records.empty?

        now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
        ids = records.map(&:id)
        placeholders = (['?'] * ids.size).join(', ')

        @db.execute(
          "UPDATE memories SET access_count = access_count + 1, last_accessed_at = ? WHERE id IN (#{placeholders})",
          [now] + ids
        )
      rescue StandardError
        # Access tracking is best-effort; never fail a search because of it.
        nil
      end

      # @param raw [String, Hash, nil]
      # @return [Hash]
      def parse_json(raw)
        case raw
        when Hash then raw
        when String then JSON.parse(raw, symbolize_names: true)
        else {}
        end
      rescue JSON::ParserError
        {}
      end
    end
  end
end
