# frozen_string_literal: true

require 'pastel'

module RubynCode
  module Output
    class DiffRenderer
      # Immutable value object representing a single hunk in a unified diff.
      Hunk = Data.define(:old_start, :old_count, :new_start, :new_count, :lines)

      # Represents a single diff line with its type and content.
      DiffLine = Data.define(:type, :content) do
        def addition? = type == :add
        def deletion? = type == :delete
        def context?  = type == :context
      end

      attr_reader :pastel

      # @param enabled [Boolean] whether color output is enabled
      # @param context_lines [Integer] number of context lines around changes
      def initialize(enabled: $stdout.tty?, context_lines: 3)
        @pastel = Pastel.new(enabled: enabled)
        @context_lines = context_lines
      end

      # Renders a unified diff between old_text and new_text.
      #
      # @param old_text [String] the original text
      # @param new_text [String] the modified text
      # @param filename [String] the filename to display in the diff header
      # @return [String] the rendered, colorized diff output
      def render(old_text, new_text, filename: 'file')
        old_lines = old_text.lines.map(&:chomp)
        new_lines = new_text.lines.map(&:chomp)

        hunks = compute_hunks(old_lines, new_lines)
        return pastel.dim('No differences found.') if hunks.empty?

        parts = []
        parts << render_header(filename)
        hunks.each { |hunk| parts << render_hunk(hunk) }
        parts << ''

        result = parts.join("\n")
        $stdout.puts(result)
        result
      end

      private

      def render_header(filename)
        [
          pastel.bold("--- a/#{filename}"),
          pastel.bold("+++ b/#{filename}")
        ].join("\n")
      end

      def render_hunk(hunk)
        header = pastel.cyan(
          "@@ -#{hunk.old_start},#{hunk.old_count} +#{hunk.new_start},#{hunk.new_count} @@"
        )

        rendered_lines = hunk.lines.map do |diff_line|
          case diff_line
          in DiffLine[type: :add, content:]
            pastel.green("+#{content}")
          in DiffLine[type: :delete, content:]
            pastel.red("-#{content}")
          in DiffLine[type: :context, content:]
            pastel.dim(" #{content}")
          end
        end

        [header, *rendered_lines].join("\n")
      end

      # Computes unified-diff hunks using the Myers diff algorithm (simple LCS approach).
      def compute_hunks(old_lines, new_lines)
        lcs_table = build_lcs_table(old_lines, new_lines)
        raw_diff = backtrack_diff(lcs_table, old_lines, new_lines)
        group_into_hunks(raw_diff, old_lines, new_lines)
      end

      # Builds the LCS length table for two arrays of lines.
      def build_lcs_table(old_lines, new_lines)
        m = old_lines.size
        n = new_lines.size
        table = Array.new(m + 1) { Array.new(n + 1, 0) }

        (1..m).each do |i|
          (1..n).each do |j|
            table[i][j] = if old_lines[i - 1] == new_lines[j - 1]
                            table[i - 1][j - 1] + 1
                          else
                            [table[i - 1][j], table[i][j - 1]].max
                          end
          end
        end

        table
      end

      # Backtracks through the LCS table to produce a sequence of diff operations.
      # Returns an array of [:equal, :delete, :add] paired with line indices.
      def backtrack_diff(table, old_lines, new_lines)
        result = []
        i = old_lines.size
        j = new_lines.size

        while i.positive? || j.positive?
          if i.positive? && j.positive? && old_lines[i - 1] == new_lines[j - 1]
            result.unshift([:equal, i - 1, j - 1])
            i -= 1
            j -= 1
          elsif j.positive? && (i.zero? || table[i][j - 1] >= table[i - 1][j])
            result.unshift([:add, nil, j - 1])
            j -= 1
          elsif i.positive?
            result.unshift([:delete, i - 1, nil])
            i -= 1
          end
        end

        result
      end

      # Groups raw diff operations into hunks with surrounding context lines.
      def group_into_hunks(raw_diff, old_lines, new_lines)
        # Identify change indices (non-equal operations)
        change_indices = raw_diff.each_index.reject { |idx| raw_diff[idx][0] == :equal }
        return [] if change_indices.empty?

        # Group changes that are within context_lines of each other
        groups = []
        current_group = [change_indices.first]

        change_indices.drop(1).each do |idx|
          if idx - current_group.last <= (@context_lines * 2) + 1
            current_group << idx
          else
            groups << current_group
            current_group = [idx]
          end
        end
        groups << current_group

        # Build hunks from groups
        groups.map do |group|
          range_start = [group.first - @context_lines, 0].max
          range_end = [group.last + @context_lines, raw_diff.size - 1].min

          lines = []
          old_start = nil
          new_start = nil
          old_count = 0
          new_count = 0

          (range_start..range_end).each do |idx|
            op, old_idx, new_idx = raw_diff[idx]

            case op
            when :equal
              old_start ||= old_idx + 1
              new_start ||= new_idx + 1
              lines << DiffLine.new(type: :context, content: old_lines[old_idx])
              old_count += 1
              new_count += 1
            when :delete
              old_start ||= old_idx + 1
              new_start ||= (new_idx || find_new_start(raw_diff, idx)) + 1
              lines << DiffLine.new(type: :delete, content: old_lines[old_idx])
              old_count += 1
            when :add
              old_start ||= (old_idx || find_old_start(raw_diff, idx)) + 1
              new_start ||= new_idx + 1
              lines << DiffLine.new(type: :add, content: new_lines[new_idx])
              new_count += 1
            end
          end

          old_start ||= 1
          new_start ||= 1

          Hunk.new(
            old_start: old_start,
            old_count: old_count,
            new_start: new_start,
            new_count: new_count,
            lines: lines.freeze
          )
        end
      end

      # Find the nearest new-side line number for context when a delete has no new_idx.
      def find_new_start(raw_diff, from_idx)
        ((from_idx + 1)...raw_diff.size).each do |i|
          return raw_diff[i][2] if raw_diff[i][2]
        end
        0
      end

      # Find the nearest old-side line number for context when an add has no old_idx.
      def find_old_start(raw_diff, from_idx)
        ((from_idx + 1)...raw_diff.size).each do |i|
          return raw_diff[i][1] if raw_diff[i][1]
        end
        0
      end
    end
  end
end
