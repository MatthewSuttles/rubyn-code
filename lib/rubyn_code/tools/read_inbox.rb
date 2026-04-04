# frozen_string_literal: true

require_relative 'base'
require_relative 'registry'

module RubynCode
  module Tools
    # Tool for reading unread messages from a teammate's inbox.
    class ReadInbox < Base
      TOOL_NAME = 'read_inbox'
      DESCRIPTION = "Reads all unread messages from the agent's inbox and marks them as read."
      PARAMETERS = {
        name: { type: :string, required: true, description: 'The agent name whose inbox to read' }
      }.freeze
      RISK_LEVEL = :read
      REQUIRES_CONFIRMATION = false

      # @param project_root [String]
      # @param mailbox [Teams::Mailbox] the team mailbox instance
      def initialize(project_root:, mailbox:)
        super(project_root: project_root)
        @mailbox = mailbox
      end

      # Reads and returns all unread messages for the given agent.
      #
      # @param name [String] the reader's agent name
      # @return [String] formatted messages or a notice if the inbox is empty
      def execute(name:)
        raise Error, 'Agent name is required' if name.nil? || name.strip.empty?

        messages = @mailbox.read_inbox(name)

        return "No unread messages for '#{name}'." if messages.empty?

        formatted = messages.map.with_index(1) do |msg, idx|
          format_message(idx, msg)
        end

        header = "#{messages.size} message#{'s' if messages.size != 1} for '#{name}':\n"
        header + formatted.join("\n")
      end

      private

      # Formats a single message for display.
      #
      # @param index [Integer] message number
      # @param msg [Hash] the parsed message hash
      # @return [String]
      def format_message(index, msg)
        lines = []
        lines << "--- Message #{index} ---"
        lines << "  From: #{msg[:from]}"
        lines << "  Type: #{msg[:message_type]}"
        lines << "  Time: #{msg[:timestamp]}"
        lines << "  Content: #{msg[:content]}"
        lines.join("\n")
      end
    end

    Registry.register(ReadInbox)
  end
end
