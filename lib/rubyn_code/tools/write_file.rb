# frozen_string_literal: true

require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class WriteFile < Base
      TOOL_NAME = "write_file"
      DESCRIPTION = "Writes content to a file. Creates parent directories if needed."
      PARAMETERS = {
        path: { type: :string, required: true, description: "Path to the file to write (relative to project root or absolute)" },
        content: { type: :string, required: true, description: "Content to write to the file" }
      }.freeze
      RISK_LEVEL = :write
      REQUIRES_CONFIRMATION = false

      def execute(path:, content:)
        resolved = safe_path(path)

        FileUtils.mkdir_p(File.dirname(resolved))
        bytes = File.write(resolved, content)

        "Successfully wrote #{bytes} bytes to #{path}"
      end
    end

    Registry.register(WriteFile)
  end
end
