# frozen_string_literal: true

module RubynCode
  module Tools
    class Base
      TOOL_NAME = ''
      DESCRIPTION = ''
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

      # Safe replacement for Open3.capture3 that avoids Ruby 4.0's IOError
      # when threads race on stream closure. All tools should use this instead
      # of Open3.capture3 directly.
      def safe_capture3(*cmd, chdir: project_root, timeout: 120, **)
        stdin, stdout_io, stderr_io, wait_thr = Open3.popen3(*cmd, chdir: chdir, **)
        stdin.close

        stdout = +''
        stderr = +''

        out_reader = Thread.new do
          stdout << stdout_io.read
        rescue StandardError
          nil
        end
        err_reader = Thread.new do
          stderr << stderr_io.read
        rescue StandardError
          nil
        end

        timed_out = false
        unless wait_thr.join(timeout)
          timed_out = true
          begin
            Process.kill('TERM', wait_thr.pid)
          rescue StandardError
            nil
          end
          sleep 0.1
          begin
            Process.kill('KILL', wait_thr.pid)
          rescue StandardError
            nil
          end
          wait_thr.join(5)
        end

        out_reader.join(5)
        err_reader.join(5)
        [stdout_io, stderr_io].each do |io|
          io.close
        rescue StandardError
          nil
        end

        raise Error, "Command timed out after #{timeout}s" if timed_out

        [stdout, stderr, wait_thr.value]
      end

      def read_file_safely(path)
        resolved = safe_path(path)
        raise Error, "File not found: #{path}" unless File.exist?(resolved)
        raise Error, "Not a file: #{path}" unless File.file?(resolved)

        resolved
      end
    end
  end
end
