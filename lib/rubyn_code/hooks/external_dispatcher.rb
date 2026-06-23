# frozen_string_literal: true

require_relative 'event_map'
require_relative 'response'
require_relative 'settings_json_loader'
require_relative 'subprocess_executor'

module RubynCode
  module Hooks
    # Dispatches hook events to external commands configured in settings.json.
    #
    # The dispatcher sits alongside the in-process Hooks::Runner. It does NOT
    # replace it — existing pre/post_tool_use YAML hooks and Ruby callables
    # keep working. New code that wants Claude Code-style control flow (block,
    # stopReason, additionalContext) fires through this dispatcher instead.
    #
    # Wire it into the agent loop wherever a return value matters:
    #
    #   response = dispatcher.fire(:pre_tool_use, tool_name:, tool_input:)
    #   raise ToolBlockedError, response.reason if response.block?
    #
    # For events where return values don't matter (e.g. SessionStart logging),
    # call #fire and ignore the response — but still inspect #stop? when the
    # caller wants to honour a stop signal mid-stream.
    class ExternalDispatcher
      DEFAULT_TIMEOUT = 60

      attr_reader :project_root, :config

      # @param project_root [String]
      # @param config [Hash<String, Array<Hash>>] result of SettingsJsonLoader#load
      # @param executor [SubprocessExecutor, nil] injectable for tests
      # @param logger [#warn, nil] injectable for tests
      def initialize(project_root:, config: nil, executor: nil, logger: nil)
        @project_root = project_root
        @config = config || SettingsJsonLoader.new(project_root: project_root).load
        @executor = executor || SubprocessExecutor.new(project_root: project_root)
        @logger = logger || method(:default_log)
      end

      # @return [Boolean] true if any external hook is configured for this event
      def configured_for?(internal_event)
        external = EventMap.external(internal_event)
        return false unless external

        Array(@config[external]).any?
      end

      # Fires all configured external hooks for the given internal event.
      #
      # Each matcher group's commands are run sequentially (the order they
      # appear in settings.json). Within a group, commands run in declared
      # order. Hook errors and timeouts are logged but do not abort the
      # remaining hooks — matching Claude Code's "best effort" semantics.
      #
      # @param internal_event [Symbol] one of TO_EXTERNAL keys
      # @param payload [Hash] event-specific payload (tool_name, tool_input, etc.)
      # @return [Response] the merged response from all hooks (first block/stop
      #   wins; additionalContext is concatenated)
      def fire(internal_event, **payload)
        external = EventMap.external(internal_event)
        return empty_response unless external

        groups = Array(@config[external])
        return empty_response if groups.empty?

        envelope = build_envelope(external, payload)
        collected = collect_responses(groups, envelope, payload)
        Response.new(raw: build_merged(collected, external))
      end

      private

      def empty_response
        Response.new(raw: {})
      end

      # Runs each configured hook command and collects its decision fields.
      # First block/stop wins; additionalContext/suppressOutput are also
      # first-wins for simplicity (matches Claude Code's documented behaviour).
      def collect_responses(groups, envelope, payload)
        accumulator = {
          block_reason: nil, stop_reason: nil,
          additional_context: nil, suppress_output: false
        }

        groups.each do |group|
          next unless matches?(group['matcher'], payload)

          group['hooks'].each do |command_cfg|
            response = invoke_command(command_cfg, envelope)
            merge_response!(accumulator, response)
          end
        end

        accumulator
      end

      def merge_response!(accumulator, response)
        return unless response

        accumulator[:block_reason]       ||= response.reason if response.block?
        accumulator[:stop_reason]        ||= response.stop_reason if response.stop?
        accumulator[:additional_context] ||= response.additional_context if response.additional_context?
        accumulator[:suppress_output]    ||= response.suppress_output?
      end

      def invoke_command(command_cfg, envelope)
        command = command_cfg['command']
        return nil if command.nil? || command.empty?

        timeout = command_cfg['timeout'] || DEFAULT_TIMEOUT
        env     = command_cfg['env'] || {}

        raw = @executor.run(
          command: command,
          env: env,
          payload: envelope,
          timeout: timeout
        )
        Response.new(raw: raw || {})
      rescue SubprocessExecutor::TimeoutError, SubprocessExecutor::ExecutionError => e
        @logger.call("[ExternalDispatcher] hook '#{command}' failed: #{e.message}")
        nil
      end

      def build_envelope(external_event, payload)
        base_envelope(external_event, payload).merge(event_specific_fields(external_event, payload)).compact
      end

      def base_envelope(external_event, payload)
        {
          'hookEventName' => external_event,
          'sessionId' => payload[:session_id] || payload['session_id'] || ENV.fetch('RUBYN_SESSION_ID', nil),
          'cwd' => @project_root,
          'transcriptPath' => payload[:transcript_path] || ENV.fetch('RUBYN_TRANSCRIPT_PATH', nil)
        }.compact
      end

      def event_specific_fields(external_event, payload)
        case external_event
        when 'PreToolUse', 'PostToolUse' then tool_envelope_fields(payload)
        when 'UserPromptSubmit'          then { 'prompt' => payload[:prompt] || payload['text'] }
        when 'Notification'              then { 'message' => payload[:message] }
        when 'SessionStart', 'SessionEnd', 'Stop', 'SubagentStop' then session_envelope_fields(payload)
        when 'PreCompact' then { 'trigger' => payload[:trigger] || 'auto' }
        else {}
        end
      end

      def tool_envelope_fields(payload)
        {
          'toolName' => payload[:tool_name] || payload['tool_name'],
          'toolInput' => payload[:tool_input] || payload['tool_input'] || {}
        }
      end

      def session_envelope_fields(payload)
        return {} unless payload[:reason]

        { 'reason' => payload[:reason] }
      end

      def matches?(matcher, payload)
        return true if matcher.nil? || matcher == '*'

        target = payload[:tool_name] || payload['tool_name'] || payload[:session_id] || payload['session_id']
        return true if target.nil? # No subject to match — accept all

        begin
          Regexp.new(matcher).match?(target.to_s)
        rescue RegexpError
          # Fall back to literal equality if matcher isn't a valid regex.
          matcher.to_s == target.to_s
        end
      end

      def build_merged(collected, hook_event_name)
        merged = {}
        merged['decision']     = 'block' if collected[:block_reason]
        merged['reason']       = collected[:block_reason] if collected[:block_reason]
        merged['stopReason']   = collected[:stop_reason] if collected[:stop_reason]
        merged['continue']     = false if collected[:stop_reason]
        merged['suppressOutput'] = true if collected[:suppress_output]
        return merged unless collected[:additional_context]

        merged['hookSpecificOutput'] = {
          'hookEventName' => hook_event_name,
          'additionalContext' => collected[:additional_context]
        }
        merged
      end

      def default_log(message)
        warn message
      end
    end
  end
end
