# frozen_string_literal: true

require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class ReadFile < Base
      TOOL_NAME = "read_file"
      DESCRIPTION = "Reads a file from the filesystem. Returns file content with line numbers prepended."
      PARAMETERS = {
        path: { type: :string, required: true, description: "Path to the file to read (relative to project root or absolute)" },
        offset: { type: :integer, required: false, description: "Line number to start reading from (1-based)" },
        limit: { type: :integer, required: false, description: "Number of lines to read" }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def execute(path:, offset: nil, limit: nil)
        resolved = read_file_safely(path)

        lines = File.readlines(resolved)

        start_line = offset ? [offset.to_i - 1, 0].max : 0
        end_line = limit ? start_line + limit.to_i : lines.length

        selected = lines[start_line...end_line] || []

        selected.each_with_index.map do |line, idx|
          line_num = start_line + idx + 1
          "#{line_num.to_s.rjust(6)}\t#{line}"
        end.join
      end
    end

    Registry.register(ReadFile)
  end
end
