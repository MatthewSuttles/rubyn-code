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

      # Suggest skills based on what the codebase index reveals about the project.
      #
      # Inspects class names, parent classes, and file paths in the index to
      # detect common Rails patterns (Devise, ActionMailer, ActiveJob, etc.)
      # and returns matching skill names.
      #
      # @param codebase_index [RubynCode::Index::CodebaseIndex, nil]
      # @param project_profile [Object, nil] reserved for future profile-based hints
      # @return [Array<String>] suggested skill names (not loaded automatically)
      def suggest_skills(codebase_index: nil, project_profile: nil) # rubocop:disable Lint/UnusedMethodArgument, Metrics/CyclomaticComplexity -- project_profile reserved for future use
        return [] unless codebase_index

        suggestions = []
        node_names = codebase_index.nodes.map { |n| n['name'].to_s }
        node_files = codebase_index.nodes.map { |n| n['file'].to_s }

        suggestions << 'authentication' if detect_devise?(node_names, node_files)
        suggestions << 'mailer'         if detect_action_mailer?(node_names, node_files)
        suggestions << 'background-job' if detect_active_job?(node_names, node_files)

        suggestions
      rescue StandardError
        []
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

      # Devise detection: look for Devise-related class names or config files.
      def detect_devise?(node_names, node_files)
        node_names.any? { |n| n.match?(/\bDevise\b/i) } ||
          node_files.any? { |f| f.include?('devise') }
      end

      # ActionMailer detection: look for mailer classes or mailer directory.
      def detect_action_mailer?(node_names, node_files)
        node_names.any? { |n| n.match?(/Mailer\b/) } ||
          node_files.any? { |f| f.include?('app/mailers/') }
      end

      # ActiveJob detection: look for job classes or jobs directory.
      def detect_active_job?(node_names, node_files)
        node_names.any? { |n| n.match?(/Job\b/) } ||
          node_files.any? { |f| f.include?('app/jobs/') }
      end
    end
  end
end
