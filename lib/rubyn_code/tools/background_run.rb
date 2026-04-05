# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    class BackgroundRun < Base
      TOOL_NAME = 'background_run'
      DESCRIPTION = 'Run a command in the background (test suites, builds, deploys). ' \
                    'Returns immediately with a job ID. Results are delivered automatically ' \
                    'before your next LLM call.'
      PARAMETERS = {
        command: {
          type: :string,
          description: 'The shell command to run in the background',
          required: true
        },
        timeout: {
          type: :integer,
          description: 'Timeout in seconds (default: 300)',
          required: false
        }
      }.freeze
      RISK_LEVEL = :execute

      attr_writer :background_worker

      def execute(command:, timeout: 300)
        return 'Error: Background worker not available. Use bash tool instead.' unless @background_worker

        job_id = @background_worker.run(command, timeout: timeout)
        "Background job started: #{job_id}\nCommand: #{command}\n" \
          "Timeout: #{timeout}s\nResults will appear automatically when complete."
      end
    end

    Registry.register(BackgroundRun)
  end
end
