# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class Glob < Base
      TOOL_NAME = 'glob'
      DESCRIPTION = 'File pattern matching. Returns sorted list of file paths matching the glob pattern.'
      PARAMETERS = {
        pattern: {
          type: :string, required: true,
          description: "Glob pattern (e.g. '**/*.rb', 'app/**/*.erb')"
        },
        path: {
          type: :string, required: false,
          description: 'Directory to search in (defaults to project root)'
        }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def self.summarize(output, args)
        pattern = args['pattern'] || args[:pattern] || ''
        count = output.to_s.strip.empty? ? 0 : output.to_s.lines.count
        "glob #{pattern} (#{count} files)"
      end

      def execute(pattern:, path: nil)
        search_dir = resolve_search_dir(path)
        full_pattern = File.join(search_dir, pattern)
        matches = Dir.glob(full_pattern, File::FNM_DOTMATCH).sort

        matches
          .select { |f| File.file?(f) }
          .reject { |f| dot_entry?(f) }
          .map { |f| relative_to_root(f) }
          .join("\n")
      end

      private

      def resolve_search_dir(path)
        search_dir = path ? safe_path(path) : project_root

        raise Error, "Directory not found: #{path || project_root}" unless File.directory?(search_dir)

        search_dir
      end

      def dot_entry?(file)
        basename = File.basename(file)
        ['.', '..'].include?(basename)
      end

      def relative_to_root(absolute_path)
        absolute_path.delete_prefix("#{project_root}/")
      end
    end

    Registry.register(Glob)
  end
end
