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
          raise PermissionDeniedError,
                "Path traversal denied: #{path} resolves outside project root"
        end

        expanded
      end

      def truncate(output, max: 10_000)
        return output if output.nil? || output.length <= max

        half = max / 2
        middle = "\n\n... [truncated #{output.length - max} characters] ...\n\n"
        "#{output[0, half]}#{middle}#{output[-half, half]}"
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

        out_reader = Thread.new { stdout << stdout_io.read rescue nil } # rubocop:disable Style/RescueModifier
        err_reader = Thread.new { stderr << stderr_io.read rescue nil } # rubocop:disable Style/RescueModifier

        wait_for_process(wait_thr, timeout)
        finalize_readers(out_reader, err_reader, stdout_io, stderr_io)

        [stdout, stderr, wait_thr.value]
      end

      def wait_for_process(wait_thr, timeout)
        return if wait_thr.join(timeout)

        kill_process(wait_thr.pid)
        wait_thr.join(5)
        raise Error, "Command timed out after #{timeout}s"
      end

      def kill_process(pid)
        Process.kill('TERM', pid) rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.1
        Process.kill('KILL', pid) rescue nil # rubocop:disable Style/RescueModifier
      end

      def finalize_readers(out_reader, err_reader, stdout_io, stderr_io)
        out_reader.join(5)
        err_reader.join(5)
        [stdout_io, stderr_io].each do |io|
          io.close
        rescue StandardError
          nil
        end
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
