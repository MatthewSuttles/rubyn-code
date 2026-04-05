# frozen_string_literal: true

require 'yaml'

module RubynCode
  module Skills
    class Document
      FRONTMATTER_PATTERN = /\A---\s*\n(.+?\n)---\s*\n(.*)\z/m

      attr_reader :name, :description, :tags, :body

      def initialize(name:, description:, tags:, body:)
        @name = name
        @description = description
        @tags = tags
        @body = body
      end

      class << self
        def parse(content, filename: nil)
          match = FRONTMATTER_PATTERN.match(content)
          match ? parse_with_frontmatter(match) : parse_without_frontmatter(content, filename)
        end

        def parse_with_frontmatter(match)
          frontmatter = YAML.safe_load(match[1], permitted_classes: [Symbol]) || {}
          new(
            name: frontmatter['name'].to_s,
            description: frontmatter['description'].to_s,
            tags: Array(frontmatter['tags']),
            body: match[2].to_s.strip
          )
        end

        def parse_without_frontmatter(content, filename)
          body = content.to_s.strip
          title = extract_title(body)
          derived_name = filename ? File.basename(filename, '.*').tr('_', '-') : title_to_name(title)

          new(
            name: derived_name,
            description: title,
            tags: derive_tags(derived_name, body),
            body: body
          )
        end

        def parse_file(path)
          raise Error, "Skill file not found: #{path}" unless File.exist?(path)
          raise Error, "Not a file: #{path}" unless File.file?(path)

          content = File.read(path, encoding: 'UTF-8')
          parse(content, filename: path)
        end

        TAG_RULES = [
          ['ruby',        /\bruby\b/i],
          ['rails',       /\brails\b/i],
          ['rspec',       /\brspec\b/i],
          ['testing',     /\b(?:test|spec|minitest)\b/i],
          ['patterns',    /\b(?:pattern|design|solid)\b/i],
          ['refactoring', /\brefactor/i]
        ].freeze

        private

        def extract_title(body)
          first_line = body.lines.first&.strip || ''
          first_line.start_with?('#') ? first_line.sub(/^#+\s*/, '') : first_line[0..80]
        end

        def title_to_name(title)
          title.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')[0..40]
        end

        def derive_tags(name, body)
          TAG_RULES.each_with_object([]) do |(tag, pattern), tags|
            tags << tag if body.match?(pattern) || name.include?(tag)
          end.uniq
        end
      end
    end
  end
end
