# frozen_string_literal: true

require 'open3'
require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class BundleAdd < Base
      TOOL_NAME = 'bundle_add'
      DESCRIPTION = 'Adds a gem to the Gemfile and installs it via `bundle add`.'
      PARAMETERS = {
        gem_name: { type: :string, required: true, description: 'Name of the gem to add' },
        version: { type: :string, required: false, description: "Version constraint (e.g. '~> 1.0')" },
        group: { type: :string, required: false, description: "Gemfile group (e.g. 'development', 'test')" }
      }.freeze
      RISK_LEVEL = :execute
      REQUIRES_CONFIRMATION = false

      def execute(gem_name:, version: nil, group: nil)
        gemfile_path = File.join(project_root, 'Gemfile')

        raise Error, 'No Gemfile found in project root. Cannot run bundle add.' unless File.exist?(gemfile_path)

        command = build_command(gem_name, version, group)
        stdout, stderr, status = safe_capture3(command, chdir: project_root)

        build_output(stdout, stderr, status)
      end

      private

      def build_command(gem_name, version, group)
        cmd = "bundle add #{gem_name}"
        cmd += " --version '#{version}'" if version
        cmd += " --group #{group}" if group
        cmd
      end

      def build_output(stdout, stderr, status)
        parts = []
        parts << stdout unless stdout.empty?
        parts << "STDERR:\n#{stderr}" unless stderr.empty?
        parts << "Exit code: #{status.exitstatus}" unless status.success?
        parts.empty? ? '(no output)' : parts.join("\n")
      end
    end

    Registry.register(BundleAdd)
  end
end
