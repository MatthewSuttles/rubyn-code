# frozen_string_literal: true

require "open3"
require "securerandom"
require "timeout"
require_relative "job"
require_relative "notifier"

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
        stdout, stderr, process_status = nil
        final_status = :completed

        begin
          Timeout.timeout(timeout_seconds) do
            stdout, stderr, process_status = Open3.capture3(command, chdir: @project_root)
          end

          final_status = process_status.success? ? :completed : :error
        rescue Timeout::Error
          final_status = :timeout
          stdout = nil
          stderr = "Command timed out after #{timeout_seconds} seconds"
        rescue StandardError => e
          final_status = :error
          stdout = nil
          stderr = e.message
        end

        result = build_result(stdout, stderr)
        completed_at = Time.now

        completed_job = @mutex.synchronize do
          @jobs[job_id] = Job.new(
            id: job_id,
            command: command,
            status: final_status,
            result: result,
            started_at: @jobs[job_id].started_at,
            completed_at: completed_at
          )
        end

        @notifier.push({
          type: :job_completed,
          job_id: job_id,
          status: final_status,
          result: result,
          duration: completed_job.duration
        })
      end

      def build_result(stdout, stderr)
        parts = []
        parts << stdout if stdout && !stdout.empty?
        parts << "STDERR: #{stderr}" if stderr && !stderr.empty?
        parts.empty? ? "(no output)" : parts.join("\n")
      end
    end
  end
end
