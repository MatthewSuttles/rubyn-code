# frozen_string_literal: true

module RubynCode
  module Skills
    class Catalog
      SKILL_GLOB = '**/*.md'

      attr_reader :skills_dirs

      def initialize(skills_dirs)
        @skills_dirs = Array(skills_dirs)
        @index = nil
      end

      def descriptions
        entries = available
        return '' if entries.empty?

        entries.map { |entry| "- /#{entry[:name]}: #{entry[:description]}" }.join("\n")
      end

      def available
        build_index unless @index
        @index
      end

      def find(name)
        entry = available.find { |e| e[:name] == name.to_s }
        entry&.fetch(:path)
      end

      private

      def build_index
        @index = []

        skills_dirs.each do |dir|
          next unless File.directory?(dir)

          Dir.glob(File.join(dir, SKILL_GLOB)).each do |path|
            entry = extract_metadata(path)
            @index << entry if entry
          end
        end

        @index.uniq! { |e| e[:name] }
      end

      def extract_metadata(path)
        header = File.read(path, 1024, encoding: 'UTF-8')
                     .encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        doc = Document.parse(header, filename: path)

        name = if doc.name.empty? || doc.name == 'unknown'
                 File.basename(path, '.md')
               else
                 doc.name
               end

        {
          name: name,
          description: doc.description,
          path: File.expand_path(path)
        }
      rescue StandardError
        nil
      end
    end
  end
end
