# frozen_string_literal: true

require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    class Compact < Base
      TOOL_NAME = "compact"
      DESCRIPTION = "Triggers manual context compaction to reduce conversation size while preserving key information."
      PARAMETERS = {
        focus: { type: :string, required: false, description: "What to focus the summary on (e.g. 'the auth refactor', 'test failures')" }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      def initialize(project_root:, context_manager: nil)
        super(project_root: project_root)
        @context_manager = context_manager
      end

      def execute(focus: nil)
        manager = @context_manager

        unless manager
          return "Context compaction is not available in this session. " \
                 "No context manager was provided."
        end

        if manager.respond_to?(:compact)
          result = manager.compact(focus: focus)
          format_result(result, focus)
        else
          "Context manager does not support compaction."
        end
      end

      private

      def format_result(result, focus)
        parts = ["Context compacted successfully."]

        if result.is_a?(Hash)
          parts << "Messages before: #{result[:before]}" if result[:before]
          parts << "Messages after: #{result[:after]}" if result[:after]
          parts << "Tokens saved: ~#{result[:tokens_saved]}" if result[:tokens_saved]
        end

        parts << "Focus: #{focus}" if focus

        parts.join("\n")
      end
    end

    Registry.register(Compact)
  end
end
