# frozen_string_literal: true

require_relative "base"
require_relative "registry"

module RubynCode
  module Tools
    # Tool for sending messages to teammates via the team mailbox.
    class SendMessage < Base
      TOOL_NAME = "send_message"
      DESCRIPTION = "Sends a message to a teammate. Used for inter-agent communication within a team."
      PARAMETERS = {
        to: { type: :string, required: true, description: "Name of the recipient teammate" },
        content: { type: :string, required: true, description: "Message content to send" },
        message_type: { type: :string, required: false, default: "message",
                        description: 'Type of message (default: "message")' }
      }.freeze
      RISK_LEVEL = :write
      REQUIRES_CONFIRMATION = false

      # @param project_root [String]
      # @param mailbox [Teams::Mailbox] the team mailbox instance
      # @param sender_name [String] the name of the sending agent
      def initialize(project_root:, mailbox:, sender_name:)
        super(project_root: project_root)
        @mailbox = mailbox
        @sender_name = sender_name
      end

      # Sends a message to the specified teammate.
      #
      # @param to [String] recipient name
      # @param content [String] message body
      # @param message_type [String] type of message
      # @return [String] confirmation with the message id
      def execute(to:, content:, message_type: "message")
        raise Error, "Recipient name is required" if to.nil? || to.strip.empty?
        raise Error, "Message content is required" if content.nil? || content.strip.empty?

        message_id = @mailbox.send(
          from: @sender_name,
          to: to,
          content: content,
          message_type: message_type
        )

        "Message sent to '#{to}' (id: #{message_id}, type: #{message_type})"
      end
    end

    Registry.register(SendMessage)
  end
end
