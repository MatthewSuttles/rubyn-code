# frozen_string_literal: true

require "open3"
require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class RailsGenerate < Base
      TOOL_NAME = "rails_generate"
      DESCRIPTION = "Runs a Rails generator command. Validates that the project is a Rails application."
      PARAMETERS = {
        generator: { type: :string, required: true, description: "Generator name (e.g. 'model', 'controller', 'migration')" },
        args: { type: :string, required: true, description: "Arguments for the generator (e.g. 'User name:string email:string')" }
      }.freeze
      RISK_LEVEL = :execute
      REQUIRES_CONFIRMATION = false

      def execute(generator:, args:)
        validate_rails_project!

        command = "bundle exec rails generate #{generator} #{args}"
        stdout, stderr, status = Open3.capture3(command, chdir: project_root)

        build_output(stdout, stderr, status)
      end

      private

      def validate_rails_project!
        gemfile_path = File.join(project_root, "Gemfile")

        unless File.exist?(gemfile_path)
          raise Error, "No Gemfile found. This does not appear to be a Ruby project."
        end

        gemfile_content = File.read(gemfile_path)
        unless gemfile_content.match?(/['"]rails['"]/)
          raise Error, "Gemfile does not include Rails. This does not appear to be a Rails project."
        end
      end

      def build_output(stdout, stderr, status)
        parts = []
        parts << stdout unless stdout.empty?
        parts << "STDERR:\n#{stderr}" unless stderr.empty?
        parts << "Exit code: #{status.exitstatus}" unless status.success?
        parts.empty? ? "(no output)" : parts.join("\n")
      end
    end

    Registry.register(RailsGenerate)
  end
end
