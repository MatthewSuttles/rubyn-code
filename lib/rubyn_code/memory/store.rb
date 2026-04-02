# frozen_string_literal: true

require "securerandom"
require "json"
require_relative "models"

module RubynCode
  module Memory
    # Writes and manages memories in SQLite, backed by an FTS5 full-text
    # search index for fast retrieval. Handles expiration and relevance
    # decay to keep the memory store manageable over time.
    class Store
      # @param db [DB::Connection] database connection
      # @param project_path [String] scoping path for this memory store
      def initialize(db, project_path:)
        @db = db
        @project_path = project_path
        ensure_tables
      end

      # Persists a new memory and updates the FTS index.
      #
      # @param content [String] the memory content
      # @param tier [String] retention tier ("short", "medium", "long")
      # @param category [String, nil] classification category
      # @param metadata [Hash] arbitrary metadata
      # @param expires_at [String, nil] ISO 8601 expiration timestamp
      # @return [MemoryRecord] the created record
      def write(content:, tier: "medium", category: nil, metadata: {}, expires_at: nil)
        validate_tier!(tier)
        validate_category!(category) if category

        id = SecureRandom.uuid
        now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
        meta_json = JSON.generate(metadata)

        @db.execute(<<~SQL, [id, @project_path, tier, category, content, 1.0, 0, now, expires_at, meta_json, now])
          INSERT INTO memories (id, project_path, tier, category, content,
                                relevance_score, access_count, last_accessed_at,
                                expires_at, metadata, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        SQL

        MemoryRecord.new(
          id: id, project_path: @project_path, tier: tier, category: category,
          content: content, relevance_score: 1.0, access_count: 0,
          last_accessed_at: now, expires_at: expires_at, metadata: metadata,
          created_at: now
        )
      end

      # Updates attributes on an existing memory.
      #
      # @param id [String] the memory ID
      # @param attrs [Hash] attributes to update (content, tier, category, metadata, expires_at, relevance_score)
      # @return [void]
      def update(id, **attrs)
        return if attrs.empty?

        sets = []
        params = []

        attrs.each do |key, value|
          case key
          when :content
            sets << "content = ?"
            params << value
          when :tier
            validate_tier!(value)
            sets << "tier = ?"
            params << value
          when :category
            validate_category!(value) if value
            sets << "category = ?"
            params << value
          when :metadata
            sets << "metadata = ?"
            params << JSON.generate(value)
          when :expires_at
            sets << "expires_at = ?"
            params << value
          when :relevance_score
            sets << "relevance_score = ?"
            params << value.to_f
          end
        end

        return if sets.empty?

        params << id
        @db.execute(
          "UPDATE memories SET #{sets.join(', ')} WHERE id = ? AND project_path = '#{@project_path}'",
          params
        )

        # Content changes are picked up by LIKE-based search — no FTS sync needed
      end

      # Deletes a memory and its FTS index entry.
      #
      # @param id [String]
      # @return [void]
      def delete(id)
        @db.execute("DELETE FROM memories WHERE id = ? AND project_path = ?", [id, @project_path])
      end

      # Removes all memories whose expires_at is in the past.
      #
      # @return [Integer] number of expired memories deleted
      def expire_old!
        now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")

        expired_ids = @db.query(
          "SELECT id FROM memories WHERE project_path = ? AND expires_at IS NOT NULL AND expires_at < ?",
          [@project_path, now]
        ).to_a.map { |row| row["id"] }

        return 0 if expired_ids.empty?

        placeholders = (["?"] * expired_ids.size).join(", ")
        @db.execute(
          "DELETE FROM memories WHERE id IN (#{placeholders}) AND project_path = ?",
          expired_ids + [@project_path]
        )

        expired_ids.size
      end

      # Reduces the relevance_score of memories that have not been accessed
      # recently, simulating natural memory decay.
      #
      # @param decay_rate [Float] amount to subtract from relevance_score (default 0.01)
      # @return [void]
      def decay!(decay_rate: 0.01)
        cutoff = (Time.now.utc - 86_400).strftime("%Y-%m-%d %H:%M:%S") # 24 hours ago

        @db.execute(<<~SQL, [decay_rate, @project_path, cutoff])
          UPDATE memories
          SET relevance_score = MAX(0.0, relevance_score - ?)
          WHERE project_path = ?
            AND last_accessed_at < ?
        SQL
      end

      private

      def ensure_tables
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS memories (
            id              TEXT PRIMARY KEY,
            project_path    TEXT NOT NULL,
            tier            TEXT NOT NULL DEFAULT 'medium',
            category        TEXT,
            content         TEXT NOT NULL,
            relevance_score REAL NOT NULL DEFAULT 1.0,
            access_count    INTEGER NOT NULL DEFAULT 0,
            last_accessed_at TEXT,
            expires_at      TEXT,
            metadata        TEXT DEFAULT '{}',
            created_at      TEXT NOT NULL
          )
        SQL

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_memories_project_tier
          ON memories (project_path, tier)
        SQL

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_memories_project_category
          ON memories (project_path, category)
        SQL

        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_memories_expires_at
          ON memories (expires_at) WHERE expires_at IS NOT NULL
        SQL

        # Search uses LIKE queries — no FTS table needed
      end

      # @param tier [String]
      # @raise [ArgumentError]
      def validate_tier!(tier)
        return if VALID_TIERS.include?(tier)

        raise ArgumentError, "Invalid tier: #{tier.inspect}. Must be one of: #{VALID_TIERS.join(', ')}"
      end

      # @param category [String]
      # @raise [ArgumentError]
      def validate_category!(category)
        return if VALID_CATEGORIES.include?(category)

        raise ArgumentError, "Invalid category: #{category.inspect}. Must be one of: #{VALID_CATEGORIES.join(', ')}"
      end
    end
  end
end
