# frozen_string_literal: true

module RubynCode
  module Tools
    class Base
      TOOL_NAME = ""
      DESCRIPTION = ""
      PARAMETERS = {}.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      class << self
        def tool_name
          const_get(:TOOL_NAME)
        end

        def description
          const_get(:DESCRIPTION)
        end

        def parameters
          const_get(:PARAMETERS)
        end

        def risk_level
          const_get(:RISK_LEVEL)
        end

        def requires_confirmation?
          const_get(:REQUIRES_CONFIRMATION)
        end

        def to_schema
          {
            name: tool_name,
            description: description,
            input_schema: Schema.build(parameters)
          }
        end
      end

      attr_reader :project_root

      def initialize(project_root:)
        @project_root = File.expand_path(project_root)
      end

      def execute(**params)
        raise NotImplementedError, "#{self.class}#execute must be implemented"
      end

      def safe_path(path)
        expanded = if Pathname.new(path).absolute?
                     File.expand_path(path)
                   else
                     File.expand_path(path, project_root)
                   end

        unless expanded.start_with?(project_root)
          raise PermissionDeniedError, "Path traversal denied: #{path} resolves outside project root"
        end

        expanded
      end

      def truncate(output, max: 10_000)
        return output if output.nil? || output.length <= max

        half = max / 2
        "#{output[0, half]}\n\n... [truncated #{output.length - max} characters] ...\n\n#{output[-half, half]}"
      end

      private

      def read_file_safely(path)
        resolved = safe_path(path)
        raise Error, "File not found: #{path}" unless File.exist?(resolved)
        raise Error, "Not a file: #{path}" unless File.file?(resolved)

        resolved
      end
    end
  end
end
