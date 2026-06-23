# frozen_string_literal: true

require 'json'

module RubynCode
  module Hooks
    # Loads external hook commands from a Claude Code-compatible settings.json.
    #
    # Schema (matches Claude Code's hook config):
    #
    #   {
    #     "hooks": {
    #       "PreToolUse": [
    #         {
    #           "matcher": "bash|write_file",        // regex or "*"
    #           "hooks": [
    #             { "type": "command",
    #               "command": "/usr/local/bin/policy-check",
    #               "timeout": 60,
    #               "env": { "FOO": "bar" }            // optional
    #             }
    #           ]
    #         }
    #       ],
    #       "PostToolUse":      [ ... ],
    #       "UserPromptSubmit": [ ... ],
    #       "SessionStart":     [ ... ],
    #       "SessionEnd":       [ ... ],
    #       "Stop":             [ ... ],
    #       "SubagentStop":     [ ... ],
    #       "PreCompact":       [ ... ],
    #       "Notification":     [ ... ]
    #     }
    #   }
    #
    # "matcher" may be:
    #   - a regex string matched against the tool name (PreToolUse/PostToolUse)
    #     or the session id (other events accept any value);
    #   - "*" to match everything;
    #   - omitted/null to match everything.
    #
    # The loader does not validate that commands exist on disk — that's the
    # Executor's job (it will fail at fire time with a clear error).
    class SettingsJsonLoader
      class LoadError < RubynCode::Error
      end

      # @return [Array<String>] paths the loader will try, in order
      attr_reader :search_paths

      # @param project_root [String] used to locate .rubyn-code/settings.json
      # @param home_dir [String, nil] override for ~/.rubyn-code; defaults to Defaults::HOME_DIR
      def initialize(project_root:, home_dir: nil)
        @home_dir = home_dir || Config::Defaults::HOME_DIR
        @project_root = project_root
        @search_paths = [
          File.join(@project_root, '.rubyn-code', 'settings.json'),
          File.join(@home_dir, 'settings.json')
        ].freeze
      end

      # Loads and merges settings.json from project + global.
      #
      # Project wins for the same matcher/event combination: if both files
      # define a hook for the same event, the project's hook runs first and
      # the global hook runs after, mirroring Claude Code's behaviour.
      #
      # @return [Hash<String, Array<Hash>>] { event_name => [matcher_group, ...] }
      #   where each matcher_group is { "matcher" => String, "hooks" => [command_hash, ...] }
      def load
        merged = {}
        @search_paths.each do |path|
          next unless File.exist?(path)

          data = parse_file(path)
          merge_into!(merged, data['hooks'] || {})
        end
        merged
      end

      private

      def parse_file(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise LoadError, "Failed to parse hook settings at #{path}: #{e.message}"
      end

      def merge_into!(merged, hooks_section)
        hooks_section.each do |event_name, matcher_groups|
          next unless matcher_groups.is_a?(Array)

          merged[event_name] ||= []
          matcher_groups.each do |group|
            next unless group.is_a?(Hash)

            commands = Array(group['hooks']).select { |h| h.is_a?(Hash) && h['type'] == 'command' }
            next if commands.empty?

            merged[event_name] << {
              'matcher' => group['matcher'] || '*',
              'hooks' => commands
            }
          end
        end
      end
    end
  end
end
