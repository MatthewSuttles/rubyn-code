# frozen_string_literal: true

require 'open3'
require 'timeout'
require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class Bash < Base
      TOOL_NAME = 'bash'
      DESCRIPTION = 'Runs a shell command in the project directory. Blocks dangerous patterns ' \
                    'and scrubs sensitive environment variables.'
      PARAMETERS = {
        command: { type: :string, required: true, description: 'The shell command to execute' },
        timeout: { type: :integer, required: false, default: 120, description: 'Timeout in seconds (default: 120)' }
      }.freeze
      RISK_LEVEL = :execute
      REQUIRES_CONFIRMATION = true

      def execute(command:, timeout: 120)
        validate_command!(command)

        stdout, stderr, status = safe_capture3(scrubbed_env, command, chdir: project_root, timeout: timeout)

        build_output(stdout, stderr, status)
      end

      private

      def validate_command!(command)
        Config::Defaults::DANGEROUS_PATTERNS.each do |pattern|
          raise PermissionDeniedError, "Blocked dangerous command pattern: '#{pattern}'" if command.include?(pattern)
        end
      end

      def scrubbed_env
        env = ENV.to_h.dup

        env.each_key do |key|
          if Config::Defaults::SCRUB_ENV_VARS.any? { |sensitive| key.upcase.include?(sensitive) }
            env[key] = '[SCRUBBED]'
          end
        end

        env
      end

      def build_output(stdout, stderr, status)
        parts = []

        parts << stdout unless stdout.empty?

        parts << "STDERR:\n#{stderr}" unless stderr.empty?

        parts << "Exit code: #{status.exitstatus}" unless status.success?

        parts.empty? ? '(no output)' : parts.join("\n")
      end
    end

    Registry.register(Bash)
  end
end
