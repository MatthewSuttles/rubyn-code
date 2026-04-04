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

          if match
            frontmatter = YAML.safe_load(match[1], permitted_classes: [Symbol]) || {}
            body = match[2].to_s.strip

            new(
              name: frontmatter['name'].to_s,
              description: frontmatter['description'].to_s,
              tags: Array(frontmatter['tags']),
              body: body
            )
          else
            body = content.to_s.strip
            title = extract_title(body)
            derived_name = filename ? File.basename(filename, '.*').tr('_', '-') : title_to_name(title)
            tags = derive_tags(derived_name, body)

            new(
              name: derived_name,
              description: title,
              tags: tags,
              body: body
            )
          end
        end

        def parse_file(path)
          raise Error, "Skill file not found: #{path}" unless File.exist?(path)
          raise Error, "Not a file: #{path}" unless File.file?(path)

          content = File.read(path, encoding: 'UTF-8')
          parse(content, filename: path)
        end

        private

        def extract_title(body)
          first_line = body.lines.first&.strip || ''
          first_line.start_with?('#') ? first_line.sub(/^#+\s*/, '') : first_line[0..80]
        end

        def title_to_name(title)
          title.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')[0..40]
        end

        def derive_tags(name, body)
          tags = []
          tags << 'ruby' if body.match?(/\bruby\b/i) || name.include?('ruby')
          tags << 'rails' if body.match?(/\brails\b/i) || name.include?('rails')
          tags << 'rspec' if body.match?(/\brspec\b/i) || name.include?('rspec')
          tags << 'testing' if body.match?(/\b(test|spec|minitest)\b/i)
          tags << 'patterns' if body.match?(/\b(pattern|design|solid)\b/i)
          tags << 'refactoring' if body.match?(/\brefactor/i)
          tags.uniq
        end
      end
    end
  end
end
