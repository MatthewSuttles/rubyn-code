# frozen_string_literal: true

module RubynCode
  module Tools
    # Searches VS Code workspace symbols via the language server.
    # Only available when running in IDE mode.
    class IdeSymbols < Base
      TOOL_NAME = 'ide_symbols'
      DESCRIPTION = 'Search workspace symbols (classes, methods, modules) via VS Code language server. Only available in IDE mode.'
      PARAMETERS = {
        query: {
          type: 'string',
          description: 'Symbol search query (e.g. "User", "authenticate")',
          required: true
        }
      }.freeze
      RISK_LEVEL = :read

      def initialize(project_root:, ide_client: nil)
        super(project_root: project_root)
        @ide_client = ide_client
      end

      def execute(**params)
        unless @ide_client
          return 'IDE symbols are only available when running inside VS Code.'
        end

        query = params[:query] || ''
        return 'Query is required.' if query.empty?

        result = @ide_client.request('ide/getWorkspaceSymbols', { query: query }, timeout: 10)
        symbols = result['symbols'] || []

        return "No symbols found matching '#{query}'." if symbols.empty?

        lines = symbols.first(50).map do |s|
          container = s['containerName'] ? " (in #{s['containerName']})" : ''
          line_info = s['line'] ? ":#{s['line']}" : ''
          "#{s['kind']} #{s['name']}#{container} — #{s['file']}#{line_info}"
        end

        header = "Found #{symbols.size} symbol(s) matching '#{query}':"
        ([header] + lines).join("\n")
      end

      def self.summarize(output, _args)
        first_line = output.lines.first&.strip || ''
        first_line.start_with?('Found') ? first_line : ''
      end
    end
  end
end
