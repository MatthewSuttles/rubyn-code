# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class EditFile < Base
      TOOL_NAME = 'edit_file'
      DESCRIPTION = 'Performs exact string replacement in a file. ' \
                    'Fails if old_text is not found or is ambiguous.'
      PARAMETERS = {
        path: { type: :string, required: true,
                description: 'Path to the file to edit' },
        old_text: { type: :string, required: true,
                    description: 'The exact text to find and replace' },
        new_text: { type: :string, required: true,
                    description: 'The replacement text' },
        replace_all: { type: :boolean, required: false, default: false,
                       description: 'Replace all occurrences (default: false)' }
      }.freeze
      RISK_LEVEL = :write
      REQUIRES_CONFIRMATION = false

      # Take the first line of the tool's output, which is already formatted
      # as "Edited /path.rb (N replacements)".
      def self.summarize(output, _args)
        output.to_s.lines.first.to_s.chomp[0, 200]
      end

      def execute(path:, old_text:, new_text:, replace_all: false)
        resolved = read_file_safely(path)
        content = File.read(resolved)

        validate_occurrences!(path, content, old_text, replace_all)

        new_content = apply_replacement(content, old_text, new_text, replace_all)
        File.write(resolved, new_content)

        format_diff_result(path, content, old_text, new_text, replace_all)
      end

      # Compute the proposed file content without writing to disk.
      # Used by IDE mode to preview the edit in a diff view before the user
      # accepts. Raises if old_text is missing or ambiguous, same as execute.
      #
      # @return [Hash] { content: String, type: 'modify' }
      def preview_content(path:, old_text:, new_text:, replace_all: false)
        resolved = read_file_safely(path)
        content = File.read(resolved)

        validate_occurrences!(path, content, old_text, replace_all)

        { content: apply_replacement(content, old_text, new_text, replace_all), type: 'modify' }
      end

      private

      def validate_occurrences!(path, content, old_text, replace_all)
        count = content.scan(old_text).length

        raise Error, "old_text not found in #{path}. No changes made." if count.zero?

        return if replace_all || count == 1

        raise Error,
              "old_text found #{count} times in #{path}. " \
              'Use replace_all: true or provide more specific old_text.'
      end

      def apply_replacement(content, old_text, new_text, replace_all)
        replace_all ? content.gsub(old_text, new_text) : content.sub(old_text, new_text)
      end

      CONTEXT_LINES = 3 # rubocop:disable Lint/UselessConstantScoping

      def format_diff_result(path, original, old_text, new_text, replace_all)
        count = replace_all ? original.scan(old_text).length : 1
        lines = diff_header(path, count, original, old_text)
        lines.concat(diff_body(original, old_text, new_text))
        lines.join("\n")
      end

      def diff_header(path, count, original, old_text)
        line_num = find_line_number(original, old_text)
        header = ["Edited #{path} (#{count} replacement#{'s' if count > 1})"]
        header << "  @@ line #{line_num} @@" if line_num
        header
      end

      def diff_body(original, old_text, new_text)
        lines = context_before(original, old_text)
        old_text.lines.each { |l| lines << "  - #{l.chomp}" }
        new_text.lines.each { |l| lines << "  + #{l.chomp}" }
        lines.concat(context_after(original, old_text))
      end

      def context_before(content, text)
        idx = content.index(text)
        return [] unless idx

        before = content[0...idx].lines.last(CONTEXT_LINES)
        before.map { |l| "    #{l.chomp}" }
      end

      def context_after(content, text)
        idx = content.index(text)
        return [] unless idx

        after_start = idx + text.length
        after = content[after_start..].lines.first(CONTEXT_LINES)
        after.map { |l| "    #{l.chomp}" }
      end

      def find_line_number(content, text)
        idx = content.index(text)
        return nil unless idx

        content[0...idx].count("\n") + 1
      end
    end

    Registry.register(EditFile)
  end
end
