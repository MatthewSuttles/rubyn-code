# frozen_string_literal: true

require 'fileutils'

module RubynCode
  module CLI
    # Boots all dependencies and starts the GOLEM daemon from the CLI.
    # Handles authentication, database setup, and lifecycle output.
    #
    # Usage:
    #   rubyn-code daemon --name golem-1 --max-runs 50 --max-cost 5.0
    class DaemonRunner
      def initialize(options)
        @options = options
        @daemon_opts = options.fetch(:daemon, {})
        @renderer = Renderer.new
        @project_root = Dir.pwd
      end

      def run
        ensure_home_dir!
        ensure_auth!
        setup_database!
        display_banner!

        daemon = build_daemon
        daemon.start!

        display_shutdown_summary(daemon)
      rescue Interrupt
        @renderer.info("\nShutting down daemon...")
        display_shutdown_summary(daemon) if daemon
      rescue StandardError => e
        @renderer.error("Daemon failed: #{e.message}")
        RubynCode::Debug.warn(e.backtrace&.first(5)&.join("\n")) if @options[:debug]
        exit(1)
      end

      private

      def build_daemon # rubocop:disable Metrics/MethodLength
        Autonomous::Daemon.new(
          agent_name: @daemon_opts[:agent_name],
          role: @daemon_opts[:role],
          llm_client: @llm_client,
          project_root: @project_root,
          task_manager: @task_manager,
          mailbox: @mailbox,
          max_runs: @daemon_opts[:max_runs],
          max_cost: @daemon_opts[:max_cost],
          poll_interval: @daemon_opts[:poll_interval],
          idle_timeout: @daemon_opts[:idle_timeout],
          on_state_change: method(:on_state_change),
          on_task_complete: method(:on_task_complete),
          on_task_error: method(:on_task_error)
        )
      end

      # ── Callbacks ────────────────────────────────────────────────

      def on_state_change(old_state, new_state)
        @renderer.info("  [#{@daemon_opts[:agent_name]}] #{old_state} → #{new_state}")
      end

      def on_task_complete(task, result)
        summary = result.to_s[0..200]
        @renderer.success("  ✓ Completed: #{task.title} — #{summary}")
      end

      def on_task_error(task, error)
        @renderer.error("  ✗ Failed: #{task.title} — #{error.message}")
      end

      # ── Setup ────────────────────────────────────────────────────

      def ensure_home_dir!
        dir = Config::Defaults::HOME_DIR
        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)
      end

      def ensure_auth!
        unless Auth::TokenStore.valid?
          @renderer.error('No valid authentication found.')
          @renderer.info('Run `rubyn-code --auth` or set ANTHROPIC_API_KEY first.')
          exit(1)
        end

        @llm_client = LLM::Client.new
      end

      def setup_database!
        @db = DB::Connection.instance
        DB::Migrator.new(@db).migrate!
        @task_manager = Tasks::Manager.new(@db)
        @mailbox = Teams::Mailbox.new(@db)
      end

      def display_banner!
        @renderer.info('╔══════════════════════════════════════╗')
        @renderer.info('║        GOLEM Daemon Starting         ║')
        @renderer.info('╚══════════════════════════════════════╝')
        @renderer.info("  Agent:        #{@daemon_opts[:agent_name]}")
        @renderer.info("  Role:         #{@daemon_opts[:role]}")
        @renderer.info("  Project:      #{@project_root}")
        @renderer.info("  Max runs:     #{@daemon_opts[:max_runs]}")
        @renderer.info("  Max cost:     $#{@daemon_opts[:max_cost]}")
        @renderer.info("  Idle timeout: #{@daemon_opts[:idle_timeout]}s")
        @renderer.info("  Poll interval: #{@daemon_opts[:poll_interval]}s")
        @renderer.info('')
        @renderer.info('Waiting for tasks... (Ctrl-C to stop)')
        @renderer.info('Seed tasks via the REPL: /tasks or the task tool.')
        @renderer.info('')
      end

      def display_shutdown_summary(daemon)
        return unless daemon

        status = daemon.status
        @renderer.info('')
        @renderer.info('╔══════════════════════════════════════╗')
        @renderer.info('║        GOLEM Daemon Stopped          ║')
        @renderer.info('╚══════════════════════════════════════╝')
        @renderer.info("  Final state:    #{status[:state]}")
        @renderer.info("  Tasks completed: #{status[:runs_completed]}")
        @renderer.info("  Total cost:     $#{'%.4f' % status[:total_cost]}")
      end
    end
  end
end
