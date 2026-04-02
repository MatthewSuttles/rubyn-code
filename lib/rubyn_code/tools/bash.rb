# frozen_string_literal: true

require "open3"
require "timeout"
require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class Bash < Base
      TOOL_NAME = "bash"
      DESCRIPTION = "Runs a shell command in the project directory. Blocks dangerous patterns and scrubs sensitive environment variables."
      PARAMETERS = {
        command: { type: :string, required: true, description: "The shell command to execute" },
        timeout: { type: :integer, required: false, default: 120, description: "Timeout in seconds (default: 120)" }
      }.freeze
      RISK_LEVEL = :execute
      REQUIRES_CONFIRMATION = true

      def execute(command:, timeout: 120)
        validate_command!(command)

        env = scrubbed_env

        stdout, stderr, status = nil
        begin
          Timeout.timeout(timeout) do
            stdout, stderr, status = Open3.capture3(env, command, chdir: project_root)
          end
        rescue Timeout::Error
          raise Error, "Command timed out after #{timeout} seconds: #{command}"
        end

        output = build_output(stdout, stderr, status)
        output
      end

      private

      def validate_command!(command)
        Config::Defaults::DANGEROUS_PATTERNS.each do |pattern|
          if command.include?(pattern)
            raise PermissionDeniedError, "Blocked dangerous command pattern: '#{pattern}'"
          end
        end
      end

      def scrubbed_env
        env = ENV.to_h.dup

        env.each_key do |key|
          if Config::Defaults::SCRUB_ENV_VARS.any? { |sensitive| key.upcase.include?(sensitive) }
            env[key] = "[SCRUBBED]"
          end
        end

        env
      end

      def build_output(stdout, stderr, status)
        parts = []

        unless stdout.empty?
          parts << stdout
        end

        unless stderr.empty?
          parts << "STDERR:\n#{stderr}"
        end

        unless status.success?
          parts << "Exit code: #{status.exitstatus}"
        end

        parts.empty? ? "(no output)" : parts.join("\n")
      end
    end

    Registry.register(Bash)
  end
end
