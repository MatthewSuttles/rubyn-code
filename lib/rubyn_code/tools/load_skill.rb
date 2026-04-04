# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class LoadSkill < Base
      TOOL_NAME = 'load_skill'
      DESCRIPTION = 'Loads a skill document into the conversation context. Use /skill-name or provide the skill name.'
      PARAMETERS = {
        name: { type: :string, required: true, description: 'Name of the skill to load' }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def initialize(project_root:, skill_loader: nil)
        super(project_root: project_root)
        @skill_loader = skill_loader
      end

      def execute(name:)
        loader = @skill_loader || default_loader
        loader.load(name)
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
