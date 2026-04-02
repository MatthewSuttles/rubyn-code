# frozen_string_literal: true

require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class EditFile < Base
      TOOL_NAME = "edit_file"
      DESCRIPTION = "Performs exact string replacement in a file. Fails if old_text is not found or is ambiguous."
      PARAMETERS = {
        path: { type: :string, required: true, description: "Path to the file to edit" },
        old_text: { type: :string, required: true, description: "The exact text to find and replace" },
        new_text: { type: :string, required: true, description: "The replacement text" },
        replace_all: { type: :boolean, required: false, default: false, description: "Replace all occurrences (default: false)" }
      }.freeze
      RISK_LEVEL = :write
      REQUIRES_CONFIRMATION = false

      def execute(path:, old_text:, new_text:, replace_all: false)
        resolved = read_file_safely(path)
        content = File.read(resolved)

        occurrences = content.scan(old_text).length

        if occurrences.zero?
          raise Error, "old_text not found in #{path}. No changes made."
        end

        if !replace_all && occurrences > 1
          raise Error, "old_text found #{occurrences} times in #{path}. Use replace_all: true to replace all, or provide a more specific old_text."
        end

        new_content = if replace_all
                        content.gsub(old_text, new_text)
                      else
                        content.sub(old_text, new_text)
                      end

        File.write(resolved, new_content)

        replaced_count = replace_all ? occurrences : 1
        "Successfully replaced #{replaced_count} occurrence#{'s' if replaced_count > 1} in #{path}"
      end
    end

    Registry.register(EditFile)
  end
end
