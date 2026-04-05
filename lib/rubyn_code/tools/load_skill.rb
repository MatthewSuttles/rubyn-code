# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class LoadSkill < Base
      TOOL_NAME = 'load_skill'
      DESCRIPTION = 'Loads a best-practice skill document into context. ' \
                    'Pass the skill name (e.g. "shared-examples", "adapter", "request-specs").'
      PARAMETERS = {
        name: { type: :string, required: true,
                description: 'Skill name, e.g. "adapter", "shared-examples", "request-specs"' }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def initialize(project_root:, skill_loader: nil)
        super(project_root: project_root)
        @skill_loader = skill_loader
      end

      def execute(name:)
        # Strip leading slash — LLM sometimes sends /skill-name
        cleaned = name.to_s.sub(%r{\A/+}, '').strip
        return 'Error: skill name required' if cleaned.empty?

        loader = @skill_loader || default_loader
        loader.load(cleaned)
      end

      private

      def default_loader
        skills_dirs = [
          File.join(project_root, '.rubyn', 'skills'),
          File.join(Dir.home, '.rubyn', 'skills')
        ]
        catalog = Skills::Catalog.new(skills_dirs)
        Skills::Loader.new(catalog)
      end
    end

    Registry.register(LoadSkill)
  end
end
