# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class Grep < Base
      TOOL_NAME = 'grep'
      DESCRIPTION = 'Searches file contents using regular expressions. ' \
                    'Returns matching lines with file paths and line numbers.'
      PARAMETERS = {
        pattern: { type: :string, required: true, description: 'Regular expression pattern to search for' },
        path: { type: :string, required: false,
                description: 'File or directory to search in (defaults to project root)' },
        glob_filter: { type: :string, required: false, description: "Glob pattern to filter files (e.g. '*.rb')" },
        max_results: { type: :integer, required: false, default: 50,
                       description: 'Maximum number of matching lines to return' }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def self.summarize(output, args)
        pattern = args['pattern'] || args[:pattern] || ''
        count = output.to_s.lines.count
        no_matches = count.zero? || output.to_s.start_with?('No matches')
        no_matches ? "grep #{pattern} (0 matches)" : "grep #{pattern} (#{count} lines)"
      end

      def execute(pattern:, path: nil, glob_filter: nil, max_results: 50)
        search_path = path ? safe_path(path) : project_root
        regex = Regexp.new(pattern)

        files = collect_files(search_path, glob_filter)
        results = []

        files.each do |file|
          break if results.length >= max_results

          search_file(file, regex, results, max_results)
        end

        return "No matches found for pattern: #{pattern}" if results.empty?

        results.join("\n")
      end

      private

      def collect_files(search_path, glob_filter)
        if File.file?(search_path)
          [search_path]
        elsif File.directory?(search_path)
          glob_pattern = glob_filter || '**/*'
          Dir.glob(File.join(search_path, glob_pattern))
             .select { |f| File.file?(f) }
             .reject { |f| binary_file?(f) }
             .sort
        else
          raise Error, "Path not found: #{search_path}"
        end
      end

      def search_file(file, regex, results, max_results)
        File.foreach(file).with_index(1) do |line, line_num|
          break if results.length >= max_results

          if line.match?(regex)
            relative = file.delete_prefix("#{project_root}/")
            results << "#{relative}:#{line_num}: #{line.chomp}"
          end
        end
      rescue ArgumentError, Encoding::InvalidByteSequenceError
        # Skip files with encoding issues
      end

      def binary_file?(path)
        return true if path.match?(/\.(png|jpg|jpeg|gif|ico|woff|woff2|ttf|eot|pdf|zip|gz|tar|so|dylib|o|a)\z/i)

        sample = File.read(path, 512)
        return false if sample.nil?

        sample.bytes.any?(&:zero?)
      rescue StandardError
        true
      end
    end

    Registry.register(Grep)
  end
end
