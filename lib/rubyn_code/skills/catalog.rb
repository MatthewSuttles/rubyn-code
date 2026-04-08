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

      def list
        available.map { |e| e[:name] }
      end

      def find(name)
        entry = available.find { |e| e[:name] == name.to_s }
        entry&.fetch(:path)
      end

      # Search skill content — matches against names, descriptions, and tags.
      # Returns matching entries sorted by relevance (number of field matches).
      #
      # @param term [String] search term (case-insensitive)
      # @return [Array<Hash>] matching entries with :name, :description, :path, :relevance
      def search(term)
        pattern = /#{Regexp.escape(term)}/i
        matches = available.filter_map do |entry|
          relevance = compute_relevance(entry, pattern)
          next if relevance.zero?

          entry.merge(relevance: relevance)
        end
        matches.sort_by { |e| -e[:relevance] }
      end

      # Filter skills by category (subdirectory name).
      # Skills are organized in subdirectories under each skills_dir.
      #
      # @param category [String] category/directory name (e.g. "rails", "testing")
      # @return [Array<Hash>] matching entries
      def by_category(category)
        normalized = category.to_s.downcase
        available.select do |entry|
          path_category(entry[:path]).downcase == normalized
        end
      end

      # Return the list of unique categories derived from skill file paths.
      #
      # @return [Array<String>] sorted category names
      def categories
        available.map { |e| path_category(e[:path]) }
                 .reject(&:empty?)
                 .uniq
                 .sort
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
          tags: doc.tags,
          path: File.expand_path(path)
        }
      rescue StandardError
        nil
      end

      def compute_relevance(entry, pattern)
        score = 0
        score += 3 if entry[:name].to_s.match?(pattern)
        score += 2 if entry[:description].to_s.match?(pattern)
        Array(entry[:tags]).each { |tag| score += 1 if tag.to_s.match?(pattern) }
        score
      end

      # Derive a category from the skill file path.
      # The category is the immediate parent directory name relative to one of
      # the skills_dirs. Skills at the top level of a skills_dir have no category.
      def path_category(path)
        skills_dirs.each do |dir|
          expanded = File.expand_path(dir)
          next unless path.start_with?(expanded)

          relative = path.delete_prefix("#{expanded}/")
          parts = relative.split('/')
          return parts.size > 1 ? parts.first : ''
        end
        ''
      end
    end
  end
end
