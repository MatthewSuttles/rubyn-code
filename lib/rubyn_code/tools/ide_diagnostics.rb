# frozen_string_literal: true

module RubynCode
  module Tools
    # Retrieves VS Code diagnostics (errors/warnings from the Problems panel)
    # via the IDE RPC bridge. Only available when running in IDE mode.
    class IdeDiagnostics < Base
      TOOL_NAME = 'ide_diagnostics'
      DESCRIPTION =
        'Get VS Code diagnostics (errors, warnings) for a file or the whole workspace. ' \
        'Only available in IDE mode.'
      PARAMETERS = {
        file: {
          type: 'string',
          description: 'File path to get diagnostics for. Omit to get all workspace diagnostics.'
        }
      }.freeze
      RISK_LEVEL = :read

      def initialize(project_root:, ide_client: nil)
        super(project_root: project_root)
        @ide_client = ide_client
      end

      def execute(**params)
        unless @ide_client
          return 'IDE diagnostics are only available when running inside VS Code.'
        end

        rpc_params = {}
        rpc_params[:file] = params[:file] if params[:file]

        result = @ide_client.request('ide/getDiagnostics', rpc_params, timeout: 10)
        diagnostics = result['diagnostics'] || []

        return 'No diagnostics found.' if diagnostics.empty?

        lines = diagnostics.map do |d|
          severity = d['severity']&.upcase || 'INFO'
          source = d['source'] ? " (#{d['source']})" : ''
          "#{severity}: #{d['file']}:#{d['line']} — #{d['message']}#{source}"
        end

        lines.join("\n")
      end

      def self.summarize(output, _args)
        count = output.lines.count
        "#{count} diagnostic(s)"
      end
    end
  end
end
