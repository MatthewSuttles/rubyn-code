# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class WriteFile < Base
      TOOL_NAME = 'write_file'
      DESCRIPTION = 'Writes content to a file. Creates parent directories if needed.'
      PARAMETERS = {
        path: { type: :string, required: true,
                description: 'Path to the file to write (relative to project root or absolute)' },
        content: { type: :string, required: true, description: 'Content to write to the file' }
      }.freeze
      RISK_LEVEL = :write
      REQUIRES_CONFIRMATION = false

      PREVIEW_LINES = 15

      # Take the first line of the tool's output, which is already formatted
      # as "Updated /path.rb (N bytes)" or "Created /path.rb (N bytes)".
      def self.summarize(output, _args)
        output.to_s.lines.first.to_s.chomp[0, 200]
      end

      def execute(path:, content:)
        resolved = safe_path(path)
        existed = File.exist?(resolved)
        old_content = existed ? File.read(resolved) : nil

        FileUtils.mkdir_p(File.dirname(resolved))
        bytes = File.write(resolved, content)

        format_result(path, bytes, existed, old_content, content)
      end

      # Compute the proposed file content without writing to disk.
      # Used by IDE mode to preview the write in a diff view (modify) or
      # preview tab (create) before the user accepts.
      #
      # @return [Hash] { content: String, type: 'modify' | 'create' }
      def preview_content(path:, content:)
        resolved = safe_path(path)
        type = File.exist?(resolved) ? 'modify' : 'create'
        { content: content, type: type }
      end

      private

      def format_result(path, bytes, existed, old_content, new_content)
        lines = []

        if existed
          lines << "Updated #{path} (#{bytes} bytes)"
          lines << diff_preview(old_content, new_content)
        else
          lines << "Created #{path} (#{bytes} bytes)"
          lines << file_preview(new_content)
        end

        lines.compact.join("\n")
      end

      def file_preview(content)
        preview_lines = content.lines.first(PREVIEW_LINES)
        preview = preview_lines.each_with_index.map do |line, idx|
          "  #{(idx + 1).to_s.rjust(3)}│ #{line.chomp}"
        end.join("\n")

        remaining = content.lines.count - PREVIEW_LINES
        preview += "\n  ... (#{remaining} more lines)" if remaining.positive?
        preview
      end

      def diff_preview(old_content, new_content)
        old_lines = (old_content || '').lines.map(&:chomp)
        new_lines = new_content.lines.map(&:chomp)

        changes = simple_diff(old_lines, new_lines)
        return '  (no visible changes)' if changes.empty?

        changes.first(20).join("\n")
      end

      def simple_diff(old_lines, new_lines)
        changes = []
        max = [old_lines.length, new_lines.length].max

        max.times do |idx|
          old_line = old_lines[idx]
          new_line = new_lines[idx]

          next if old_line == new_line

          changes << "  - #{old_line}" if old_line
          changes << "  + #{new_line}" if new_line
        end

        changes
      end
    end

    Registry.register(WriteFile)
  end
end
