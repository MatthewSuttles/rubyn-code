# frozen_string_literal: true

require 'json'
require 'open3'
require 'timeout'

module RubynCode
  module Hooks
    # Spawns external hook commands and exchanges JSON with them.
    #
    # Protocol (matches Claude Code):
    #   1. Spawn the command with { env, chdir: project_root }.
    #   2. Write one JSON line to stdin:
    #        { "hookEventName": "PreToolUse",
    #          "sessionId": "...",
    #          "toolName": "bash",          // when applicable
    #          "toolInput": { ... },        // when applicable
    #          "prompt": "user text..." }   // when applicable
    #   3. Close stdin.
    #   4. Read stdout until EOF or timeout. Parse as JSON.
    #      - One JSON object spanning the whole output, OR
    #      - Newline-delimited JSON (first parseable line wins).
    #   5. Stderr is captured and logged but not parsed.
    #
    # The executor is stateless — each call spawns a fresh process. This is
    # intentional: hooks must not keep state between invocations, and process
    # startup cost (~30ms on macOS) is negligible compared to typical tool
    # execution time.
    class SubprocessExecutor
      DEFAULT_TIMEOUT = 60 # seconds

      class ExecutionError < RubynCode::Error
      end

      class TimeoutError < ExecutionError
      end

      # @param project_root [String] working directory for spawned processes
      # @param default_timeout [Integer] fallback timeout when a hook entry
      #   does not specify its own
      def initialize(project_root:, default_timeout: DEFAULT_TIMEOUT)
        @project_root = project_root
        @default_timeout = default_timeout
      end

      # Runs a single hook command with the given event payload.
      #
      # @param command [String] executable path
      # @param args [Array<String>] arguments (rarely used; settings.json
      #   typically embeds everything in the command string)
      # @param env [Hash<String, String>] additional environment variables
      # @param payload [Hash] the JSON payload (must include :hookEventName)
      # @param timeout [Integer, nil] per-call timeout override
      # @return [Hash] the parsed JSON response from stdout (empty hash if no output)
      # @raise [ExecutionError] on spawn failure
      # @raise [TimeoutError] if the command does not finish in time
      def run(command:, payload:, args: [], env: {}, timeout: nil)
        timeout ||= @default_timeout
        env = default_env.merge(env)

        stdout, _stderr, = invoke(command, args, env, payload, timeout)
        parse_response(stdout)
      rescue Timeout::Error => e
        raise TimeoutError, "Hook command '#{command}' timed out after #{timeout}s: #{e.message}"
      end

      private

      def default_env
        # Open3 replaces the entire env when env: is given, so inherit the
        # parent's environment first and add our hook-specific markers.
        ENV.to_h.merge(
          'RUBYN_HOOK_EVENT' => '1',
          'CLAUDE_PROJECT_DIR' => @project_root
        )
      end

      def invoke(command, args, env, payload, timeout)
        Timeout.timeout(timeout) do
          Open3.capture3(env, command, *args, chdir: @project_root, stdin_data: JSON.generate(payload))
        end
      rescue Errno::ENOENT => e
        raise ExecutionError, "Hook command not found: #{command} (#{e.message})"
      rescue SystemCallError => e
        raise ExecutionError, "Failed to spawn hook command '#{command}': #{e.message}"
      end

      def parse_response(stdout)
        return {} if stdout.nil? || stdout.strip.empty?

        # Try whole-output JSON first (Claude Code's preferred shape).
        begin
          parsed = JSON.parse(stdout)
          return parsed.is_a?(Hash) ? parsed : { 'output' => parsed }
        rescue JSON::ParserError
          # Fall through to line-delimited scanning.
        end

        stdout.each_line do |line|
          stripped = line.strip
          next if stripped.empty?

          begin
            parsed = JSON.parse(stripped)
            return parsed.is_a?(Hash) ? parsed : { 'output' => parsed }
          rescue JSON::ParserError
            next
          end
        end

        # Non-JSON output: treat as raw output for debugging hooks.
        { 'output' => stdout }
      end
    end
  end
end
