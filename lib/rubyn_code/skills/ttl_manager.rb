# frozen_string_literal: true

module RubynCode
  module Skills
    # Manages skill TTL (time-to-live) and size caps. Skills injected into
    # context are tracked with a turn counter; once a skill exceeds its
    # TTL it is marked for ejection during the next compaction pass.
    class TtlManager
      DEFAULT_TTL = 5          # turns
      MAX_SKILL_TOKENS = 800   # tokens
      CHARS_PER_TOKEN = 4

      Entry = Data.define(:name, :loaded_at_turn, :ttl, :token_count, :last_referenced_turn) do
        def expired?(current_turn)
          current_turn - last_referenced_turn > ttl
        end
      end

      attr_reader :entries

      def initialize
        @entries = {}
        @current_turn = 0
      end

      # Advance the turn counter. Call this once per agent loop iteration.
      def tick!
        @current_turn += 1
      end

      # Register a loaded skill with optional TTL override.
      #
      # @param name [String] skill name
      # @param content [String] skill content
      # @param ttl [Integer] turns before expiry (default 5)
      # @return [String] content, possibly truncated to size cap
      def register(name, content, ttl: DEFAULT_TTL)
        truncated = enforce_size_cap(content)
        token_count = estimate_tokens(truncated)

        @entries[name] = Entry.new(
          name: name,
          loaded_at_turn: @current_turn,
          ttl: ttl,
          token_count: token_count,
          last_referenced_turn: @current_turn
        )

        truncated
      end

      # Mark a skill as recently referenced (resets its TTL countdown).
      def touch(name)
        return unless @entries.key?(name)

        @entries[name] = @entries[name].with(last_referenced_turn: @current_turn)
      end

      # Returns names of skills that have exceeded their TTL.
      def expired_skills
        @entries.select { |_, entry| entry.expired?(@current_turn) }.keys
      end

      # Remove expired skills and return their names.
      def eject_expired!
        expired = expired_skills
        expired.each { |name| @entries.delete(name) }
        expired
      end

      # Returns total tokens used by currently loaded skills.
      def total_tokens
        @entries.values.sum(&:token_count)
      end

      # Returns stats for the analytics dashboard.
      def stats
        {
          loaded_skills: @entries.size,
          total_tokens: total_tokens,
          expired: expired_skills.size,
          current_turn: @current_turn
        }
      end

      private

      def enforce_size_cap(content)
        max_chars = MAX_SKILL_TOKENS * CHARS_PER_TOKEN
        return content if content.length <= max_chars

        content[0, max_chars] + "\n... [skill truncated to #{MAX_SKILL_TOKENS} tokens]"
      end

      def estimate_tokens(text)
        (text.bytesize.to_f / CHARS_PER_TOKEN).ceil
      end
    end
  end
end
