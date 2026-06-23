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

      # A `#` or `//` comment leader, then the lowercase tag, then the note.
      # Case-sensitive on purpose: a descriptive comment that merely starts with
      # "Chisel:" is not a marker, only the exact lowercase tag is. The
      # whitespace-only gap (\s*) after the leader also means this module's own
      # regex literal does not match itself when the repo is scanned.
      MARKER = %r{(?:#|//)\s*chisel:\s*(\S.*)}

      SCAN_EXTENSIONS = %w[.rb .rake .erb .ru .gemspec].freeze
      SKIP_DIRS = %w[.git node_modules vendor coverage tmp log].freeze

      module_function

      # @param root [String, nil] project root to scan
      # @return [Array<Item>] markers found, in file/line order
      def scan(root)
        return [] unless root && Dir.exist?(root)

        source_files(root).flat_map { |path| scan_file(root, path) }
      end

      # @return [Array<String>] absolute paths of scannable source files
      def source_files(root)
        SCAN_EXTENSIONS
          .flat_map { |ext| Dir.glob(File.join(root, '**', "*#{ext}")) }
          .reject { |path| skip?(root, path) }
          .sort
      end

      def skip?(root, path)
        rel = path.delete_prefix("#{root}/")
        SKIP_DIRS.any? { |dir| rel == dir || rel.start_with?("#{dir}/") || rel.include?("/#{dir}/") }
      end

      # @return [Array<Item>] markers in a single file ([] if it can't be read)
      def scan_file(root, path)
        rel = path.delete_prefix("#{root}/")
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
