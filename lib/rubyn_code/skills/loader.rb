# frozen_string_literal: true

module RubynCode
  module Skills
    class Loader
      attr_reader :catalog

      def initialize(catalog)
        @catalog = catalog
        @loaded = {}
      end

      def load(name)
        name = name.to_s

        return @loaded[name] if @loaded.key?(name)

        path = catalog.find(name)
        raise Error, "Skill not found: #{name}" unless path

        doc = Document.parse_file(path)
        content = format_skill(doc)

        @loaded[name] = content
        content
      end

      def loaded
        @loaded.keys
      end

      def descriptions_for_prompt
        catalog.descriptions
      end

      private

      def format_skill(doc)
        parts = []
        parts << "<skill name=\"#{escape_xml(doc.name)}\">"
        parts << doc.body unless doc.body.empty?
        parts << '</skill>'
        parts.join("\n")
      end

      def escape_xml(text)
        text.to_s
            .gsub('&', '&amp;')
            .gsub('<', '&lt;')
            .gsub('>', '&gt;')
            .gsub('"', '&quot;')
      end
    end
  end
end
