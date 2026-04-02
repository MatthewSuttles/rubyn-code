# frozen_string_literal: true

require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class Glob < Base
      TOOL_NAME = "glob"
      DESCRIPTION = "File pattern matching. Returns sorted list of file paths matching the glob pattern."
      PARAMETERS = {
        pattern: { type: :string, required: true, description: "Glob pattern (e.g. '**/*.rb', 'app/**/*.erb')" },
        path: { type: :string, required: false, description: "Directory to search in (defaults to project root)" }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def execute(pattern:, path: nil)
        search_dir = path ? safe_path(path) : project_root

        unless File.directory?(search_dir)
          raise Error, "Directory not found: #{path || project_root}"
        end

        full_pattern = File.join(search_dir, pattern)
        matches = Dir.glob(full_pattern, File::FNM_DOTMATCH).sort

        matches
          .select { |f| File.file?(f) }
          .reject { |f| File.basename(f).start_with?(".") && File.basename(f) == "." || File.basename(f) == ".." }
          .map { |f| relative_to_root(f) }
          .join("\n")
      end

      private

      def relative_to_root(absolute_path)
        absolute_path.delete_prefix("#{project_root}/")
      end
    end

    Registry.register(Glob)
  end
end
