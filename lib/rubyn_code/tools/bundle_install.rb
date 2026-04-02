# frozen_string_literal: true

require "open3"
require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class BundleInstall < Base
      TOOL_NAME = "bundle_install"
      DESCRIPTION = "Runs `bundle install` to install gem dependencies."
      PARAMETERS = {}.freeze
      RISK_LEVEL = :execute
      REQUIRES_CONFIRMATION = false

      def execute(**_params)
        gemfile_path = File.join(project_root, "Gemfile")

        unless File.exist?(gemfile_path)
          raise Error, "No Gemfile found in project root. Cannot run bundle install."
        end

        stdout, stderr, status = Open3.capture3("bundle install", chdir: project_root)

        build_output(stdout, stderr, status)
      end

      private

      def build_output(stdout, stderr, status)
        parts = []
        parts << stdout unless stdout.empty?
        parts << "STDERR:\n#{stderr}" unless stderr.empty?
        parts << "Exit code: #{status.exitstatus}" unless status.success?
        parts.empty? ? "(no output)" : parts.join("\n")
      end
    end

    Registry.register(BundleInstall)
  end
end
