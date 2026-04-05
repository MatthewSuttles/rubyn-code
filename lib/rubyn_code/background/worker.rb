# frozen_string_literal: true

require 'open3'
require 'securerandom'
require 'timeout'
require_relative 'job'
require_relative 'notifier'

module RubynCode
  module Background
    # Runs shell commands in background threads with configurable timeouts.
    # Thread-safe job tracking with a hard cap on concurrency.
    class Worker
      MAX_CONCURRENT = 5

      # @param project_root [String] working directory for spawned commands
      # @param notifier [Notifier] notification queue for completed jobs
      def initialize(project_root:, notifier: Notifier.new)
        @project_root = File.expand_path(project_root)
        @notifier = notifier
        @jobs = {}
        @threads = {}
        @mutex = Mutex.new
      end

      # Spawns a background thread to run the given command.
      #
      # @param command [String] the shell command to execute
      # @param timeout [Integer] timeout in seconds (default 120)
      # @return [String] the job ID
      # @raise [RuntimeError] if the concurrency cap is reached
      def run(command, timeout: 120)
        job_id = SecureRandom.uuid

        @mutex.synchronize do
          running = @jobs.count { |_, j| j.running? }
          if running >= MAX_CONCURRENT
            raise "Concurrency limit reached (#{MAX_CONCURRENT} jobs running). Wait for a job to finish."
          end

          job = Job.new(
            id: job_id,
            command: command,
            status: :running,
            result: nil,
            started_at: Time.now,
            completed_at: nil
          )
          @jobs[job_id] = job
        end

        thread = Thread.new { execute_job(job_id, command, timeout) }
        thread.abort_on_exception = false

        @mutex.synchronize { @threads[job_id] = thread }

        job_id
      end

      # Returns the current state of a job.
      #
      # @param job_id [String]
      # @return [Job, nil]
      def status(job_id)
        @mutex.synchronize { @jobs[job_id] }
      end

      # Delegates to the notifier to drain all pending notifications.
      #
      # @return [Array]
      def drain_notifications
        @notifier.drain
      end

      # Returns the number of currently running jobs.
      #
      # @return [Integer]
      def active_count
        @mutex.synchronize do
          @jobs.count { |_, j| j.running? }
        end
      end

      # Waits for all running threads to finish. Intended for graceful shutdown.
      #
      # @param timeout [Integer] maximum seconds to wait per thread (default 30)
      # @return [void]
      def shutdown!(timeout: 30)
        threads = @mutex.synchronize { @threads.values.dup }
        threads.each { |t| t.join(timeout) }
      end

      private

      def execute_job(job_id, command, timeout_seconds)
        stdout, stderr, final_status = run_process(command, timeout_seconds)

        result = build_result(stdout, stderr)
        completed_job = finalize_job(job_id, command, final_status, result)

        @notifier.push({
                         type: :job_completed, job_id: job_id,
                         status: final_status, result: result,
                         duration: completed_job.duration
                       })
      end

      def run_process(command, timeout_seconds)
        stdin_io, stdout_io, stderr_io, wait_thr = Open3.popen3(command, chdir: @project_root)
        stdin_io.close
        io_state = { stdout_io: stdout_io, stderr_io: stderr_io }
        out_reader, err_reader, out_buf, err_buf = start_readers(stdout_io, stderr_io)
        io_state.merge!(out_reader: out_reader, err_reader: err_reader)

        handle_wait(wait_thr, timeout_seconds, io_state)

        status = wait_thr.value.success? ? :completed : :error
        [out_buf, err_buf, status]
      rescue Timeout::Error
        [nil, "Command timed out after #{timeout_seconds} seconds", :timeout]
      rescue StandardError => e
        [nil, e.message, :error]
      end

      def start_readers(stdout_io, stderr_io)
        out_buf = +''
        err_buf = +''
        out_reader = Thread.new { out_buf << stdout_io.read rescue nil } # rubocop:disable Style/RescueModifier
        err_reader = Thread.new { err_buf << stderr_io.read rescue nil } # rubocop:disable Style/RescueModifier
        [out_reader, err_reader, out_buf, err_buf]
      end

      def handle_wait(wait_thr, timeout_seconds, io_state)
        unless wait_thr.join(timeout_seconds)
          kill_process(wait_thr)
          cleanup_io(io_state)
          raise Timeout::Error
        end

        cleanup_io(io_state)
      end

      def cleanup_io(io_state)
        cleanup_readers(io_state[:out_reader], io_state[:err_reader],
                        io_state[:stdout_io], io_state[:stderr_io])
      end

      def kill_process(wait_thr)
        Process.kill('TERM', wait_thr.pid) rescue nil # rubocop:disable Style/RescueModifier
        sleep 0.1
        Process.kill('KILL', wait_thr.pid) rescue nil # rubocop:disable Style/RescueModifier
        wait_thr.join(5)
      end

      def cleanup_readers(out_reader, err_reader, stdout_io, stderr_io)
        out_reader.join(5)
        err_reader.join(5)
        [stdout_io, stderr_io].each { |io| io.close rescue nil } # rubocop:disable Style/RescueModifier
      end

      def finalize_job(job_id, command, final_status, result)
        @mutex.synchronize do
          @jobs[job_id] = Job.new(
            id: job_id, command: command, status: final_status,
            result: result, started_at: @jobs[job_id].started_at,
            completed_at: Time.now
          )
        end
      end

      def build_result(stdout, stderr)
        parts = []
        parts << stdout if stdout && !stdout.empty?
        parts << "STDERR: #{stderr}" if stderr && !stderr.empty?
        parts.empty? ? '(no output)' : parts.join("\n")
      end
    end
  end
end
