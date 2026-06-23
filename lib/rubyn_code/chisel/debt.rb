# frozen_string_literal: true

module RubynCode
  module Chisel
    # Harvests inline deferral markers from the codebase. A marker is a code
    # comment whose text begins with the lowercase tag "chisel:" and records a
    # simplification you consciously postponed (e.g. a comment reading
    # "chisel: collapse this adapter once a second caller exists").
    #
    # Finding them is a deterministic grep — stdlib does it, so there's no LLM
    # round-trip here (Chisel's own ladder, applied to Chisel).
    module Debt
      Item = Data.define(:file, :line, :note)

      # The whole line must be a comment whose first token is the lowercase tag:
      # optional indentation, a `#` or `//` leader, then `chisel:`, then the note.
      # Anchoring to line-start means a `chisel:` substring inside a string
      # literal or a trailing code comment is NOT harvested — only a marker on its
      # own comment line is. Case-sensitive on purpose, so a descriptive comment
      # that merely starts with "Chisel:" is not a marker.
      MARKER = %r{\A\s*(?:#|//)\s*chisel:\s*(\S.*)}

      SCAN_EXTENSIONS = %w[.rb .rake .erb .ru .gemspec].freeze
      SKIP_DIRS = %w[.git node_modules vendor coverage tmp log].freeze

      module_function

      # @param root [String, nil] project root to scan
      # @return [Array<Item>] markers found, in file/line order
      def scan(root)
        return [] unless root

        base = File.expand_path(root)
        return [] unless Dir.exist?(base)

        source_files(base).flat_map { |path| scan_file(base, path) }
      end

      # @param base [String] expanded project root (no trailing slash)
      # @return [Array<String>] absolute paths of scannable source files
      def source_files(base)
        pattern = File.join(base, '**', "*{#{SCAN_EXTENSIONS.join(',')}}")
        Dir.glob(pattern).reject { |path| skip?(base, path) }.sort
      end

      def skip?(base, path)
        rel = path.delete_prefix("#{base}/")
        SKIP_DIRS.any? { |dir| rel == dir || rel.start_with?("#{dir}/") || rel.include?("/#{dir}/") }
      end

      # @return [Array<Item>] markers in a single file ([] if it can't be read)
      def scan_file(base, path)
        rel = path.delete_prefix("#{base}/")
        items = []
        File.foreach(path).with_index(1) do |line, number|
          match = MARKER.match(line)
          items << Item.new(file: rel, line: number, note: match[1].strip) if match
        end
        items
      rescue StandardError
        []
      end
    end
  end
end
