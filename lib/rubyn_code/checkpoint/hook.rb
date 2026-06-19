# frozen_string_literal: true

module RubynCode
  module Checkpoint
    # A :pre_tool_use hook that snapshots a file's original contents into the
    # current checkpoint just before a mutating tool changes it. Only the
    # file-mutating tools are watched; everything else is ignored.
    class Hook
      MUTATING_TOOLS = %w[write_file edit_file].freeze

      # @param manager [Checkpoint::Manager]
      def initialize(manager:)
        @manager = manager
      end

      # @return [nil] never blocks the tool (returns no deny decision)
      def call(tool_name:, tool_input: {}, **_kwargs)
        return nil unless MUTATING_TOOLS.include?(tool_name.to_s)

        path = tool_input[:path] || tool_input['path']
        @manager.record_file(path) if path
        nil
      end
    end
  end
end
