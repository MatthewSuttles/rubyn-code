# frozen_string_literal: true

require "open3"
require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class RunSpecs < Base
      TOOL_NAME = "run_specs"
      DESCRIPTION = "Runs RSpec or Minitest specs. Auto-detects which test framework is in use."
      PARAMETERS = {
        path: { type: :string, required: false, description: "Specific test file or directory to run" },
        format: { type: :string, required: false, default: "documentation", description: "Output format (default: 'documentation')" },
        fail_fast: { type: :boolean, required: false, description: "Stop on first failure" }
      }.freeze
      RISK_LEVEL = :execute
      REQUIRES_CONFIRMATION = false

      def execute(path: nil, format: "documentation", fail_fast: false)
        framework = detect_framework

        command = build_command(framework, path, format, fail_fast)
        stdout, stderr, status = safe_capture3(command, chdir: project_root)

        build_output(stdout, stderr, status)
      end

      private

      def detect_framework
        gemfile_path = File.join(project_root, "Gemfile")

        if File.exist?(gemfile_path)
          content = File.read(gemfile_path)
          return :rspec if content.match?(/['"]rspec['"]/) || content.match?(/['"]rspec-rails['"]/)
          return :minitest if content.match?(/['"]minitest['"]/)
        end

        return :rspec if File.exist?(File.join(project_root, ".rspec"))
        return :rspec if File.directory?(File.join(project_root, "spec"))
        return :minitest if File.directory?(File.join(project_root, "test"))

        raise Error, "Could not detect test framework. Ensure RSpec or Minitest is configured."
      end

      def build_command(framework, path, format, fail_fast)
        case framework
        when :rspec
          cmd = "bundle exec rspec"
          cmd += " --format #{format}" if format
          cmd += " --fail-fast" if fail_fast
          cmd += " #{path}" if path
          cmd
        when :minitest
          if path
            "bundle exec ruby -Itest #{path}"
          else
            "bundle exec rails test"
          end
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

    Registry.register(RunSpecs)
  end
end
