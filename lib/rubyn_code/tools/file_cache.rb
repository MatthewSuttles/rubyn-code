# frozen_string_literal: true

module RubynCode
  module Tools
    # Session-scoped file cache that serves previously-read file contents
    # when the file has not been modified since the last read. Invalidates
    # automatically when Rubyn writes or edits a file, or when mtime changes.
    class FileCache
      CHARS_PER_TOKEN = 4

      Entry = Data.define(:content, :mtime, :token_count, :read_count, :cache_hits)

      attr_reader :cache

      def initialize
        @cache = {}
      end

      # Returns cached content if the file hasn't changed, otherwise reads
      # from disk and caches the result.
      #
      # @param path [String] absolute file path
      # @return [Hash] { content:, source: :cache|:disk, tokens_saved: }
      def read(path)
        current_mtime = File.mtime(path)
        cached = @cache[path]

        if cached && cached.mtime == current_mtime
          bump_hits(path)
          { content: cached.content, source: :cache, tokens_saved: cached.token_count }
        else
          content = File.read(path)
          token_count = estimate_tokens(content)
          @cache[path] = Entry.new(
            content: content, mtime: current_mtime,
            token_count: token_count, read_count: 1, cache_hits: 0
          )
          { content: content, source: :disk, tokens_saved: 0 }
        end
      end

      # Removes a path from the cache. Called when Rubyn writes/edits the file.
      def invalidate(path)
        @cache.delete(path)
      end

      # Alias for use as a write hook.
      def on_write(path)
        invalidate(path)
      end

      # Returns true if the given path is currently cached and fresh.
      def cached?(path)
        return false unless @cache.key?(path)

        @cache[path].mtime == File.mtime(path)
      rescue Errno::ENOENT
        @cache.delete(path)
        false
      end

      # Clears the entire cache.
      def clear!
        @cache.clear
      end

      # Returns aggregate statistics about cache performance.
      def stats
        total_reads = @cache.values.sum(&:read_count)
        total_hits = @cache.values.sum(&:cache_hits)
        tokens_saved = @cache.values.sum { |e| e.cache_hits * e.token_count }
        hit_rate = total_reads.positive? ? total_hits.to_f / (total_reads + total_hits) : 0.0

        {
          entries: @cache.size,
          total_reads: total_reads,
          cache_hits: total_hits,
          hit_rate: hit_rate.round(3),
          tokens_saved: tokens_saved
        }
      end

      private

      def bump_hits(path)
        old = @cache[path]
        @cache[path] = old.with(cache_hits: old.cache_hits + 1)
      end

      def estimate_tokens(content)
        (content.bytesize.to_f / CHARS_PER_TOKEN).ceil
      end
    end
  end
end
